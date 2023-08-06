// Goals of the UI system
//
//  Desired Widgets
//  1. Text
//  2. Buttons
//  3. Sliders or Line of dots
//  4. Checkbox
//  5. Box/Window
//  6. Binding Icon Display -> Displays Mouse/Keyboard/Controller symbols maybe a clickable image
//

const std = @import("std");
const c = @import("c.zig");

pub const WidgetAlignment = enum {
    Positive,
    Centered,
    Negative,
};

fn calc_sdl_rect(size: [2]i32, position: [2]i32, scale: f32, horizontal_alignment: WidgetAlignment, vertical_alignment: WidgetAlignment) c.SDL_Rect {
    var scaled_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(size[0])) * scale));
    var scaled_height = @as(i32, @intFromFloat(@as(f32, @floatFromInt(size[1])) * scale));
    var rect = c.SDL_Rect{ .x = position[0], .y = position[1], .w = scaled_width, .h = scaled_height };

    rect.x -= switch (horizontal_alignment) {
        .Positive => 0,
        .Centered => scaled_width >> 1, //Div by 2
        .Negative => scaled_width,
    };

    rect.y -= switch (vertical_alignment) {
        .Positive => 0,
        .Centered => scaled_height >> 1, //Div by 2
        .Negative => scaled_height,
    };

    return rect;
}

pub const SdlTexture = struct {
    const Self = @This();

    handle: *c.SDL_Texture,
    width: i32,
    height: i32,

    pub fn init(texture: *c.SDL_Texture, width: i32, height: i32) Self {
        return .{
            .handle = texture,
            .width = width,
            .height = height,
        };
    }

    pub fn fromTexture(texture: *c.SDL_Texture) Self {
        var width: i32 = 0;
        var height: i32 = 0;
        _ = c.SDL_QueryTexture(texture, null, null, &width, &height);
        return .{
            .handle = texture,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Self) void {
        c.SDL_DestroyTexture(self.handle);
    }

    pub fn draw(self: Self, renderer: *c.SDL_Renderer, position: [2]i32, scale: f32, horizontal_alignment: WidgetAlignment, vertical_alignment: WidgetAlignment) void {
        var dst_rect = calc_sdl_rect([2]i32{ self.width, self.height }, position, scale, horizontal_alignment, vertical_alignment);
        _ = c.SDL_RenderCopy(renderer, self.handle, null, &dst_rect);
    }
};

pub const TextWidget = struct {
    const Self = @This();

    texture: SdlTexture,
    bg_color: ?c.SDL_Color,

    pub fn init(renderer: *c.SDL_Renderer, font: *c.TTF_Font, text: [*c]const u8, color: c.SDL_Color, bg_color: ?c.SDL_Color) Self {
        var surface = c.TTF_RenderText_Solid(font, text, color);
        defer c.SDL_FreeSurface(surface);
        var texture = SdlTexture.init(c.SDL_CreateTextureFromSurface(renderer, surface).?, surface.*.w, surface.*.h);
        return .{
            .texture = texture,
            .bg_color = bg_color,
        };
    }

    pub fn deinit(self: *Self) void {
        self.texture.deinit();
    }

    pub fn draw(self: Self, renderer: *c.SDL_Renderer, position: [2]i32, scale: f32, horizontal_alignment: WidgetAlignment, vertical_alignment: WidgetAlignment) void {
        var dst_rect = calc_sdl_rect([2]i32{ self.texture.width, self.texture.height }, position, scale, horizontal_alignment, vertical_alignment);
        if (self.bg_color) |bg_color| {
            _ = c.SDL_SetRenderDrawColor(renderer, bg_color.r, bg_color.g, bg_color.b, bg_color.a);
            _ = c.SDL_RenderFillRect(renderer, &dst_rect);
        }
        _ = c.SDL_RenderCopy(renderer, self.texture.handle, null, &dst_rect);
    }
};
