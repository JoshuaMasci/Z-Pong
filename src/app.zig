const std = @import("std");
const log = std.log;
const c = @import("c.zig");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");

pub const GameInputContext = input.InputContext{
    .name = StringHash.new("Game"),
    .buttons = &[_]StringHash{StringHash.new("Button1")},
    .axes = &[_]StringHash{StringHash.new("Axis1")},
};

pub const SdlTexture = struct {
    const Self = @This();

    handle: ?*c.SDL_Texture,
    width: i32,
    height: i32,

    pub fn fromTexture(texture: ?*c.SDL_Texture) Self {
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
};

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    window: ?*c.SDL_Window,
    sdl_renderer: ?*c.SDL_Renderer,

    input_system: *input.InputSystem,
    sdl_input_system: *sdl_input.SdlInputSystem,

    //Test Data
    some_texture: SdlTexture,
    some_font: ?*c.TTF_Font,
    some_text_texture: SdlTexture,

    pub fn init(allocator: std.mem.Allocator) !Self {
        log.info("Starting SDL2", .{});
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_JOYSTICK | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_HAPTIC) != 0) {
            std.debug.panic("SDL ERROR {s}", .{c.SDL_GetError()});
        }
        if (c.IMG_Init(c.IMG_INIT_PNG) == 0) {
            std.debug.panic("SDL_IMG ERROR {s}", .{c.IMG_GetError()});
        }
        if (c.TTF_Init() != 0) {
            std.debug.panic("SDL_TTF ERROR {s}", .{c.TTF_GetError()});
        }

        var window = c.SDL_CreateWindow("Z-Pong", 0, 0, 1920, 1080, c.SDL_WINDOW_MAXIMIZED | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI);
        var sdl_renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC).?;

        var input_system = try allocator.create(input.InputSystem);
        input_system.* = try input.InputSystem.init(
            allocator,
            &[_]input.InputContext{GameInputContext},
        );

        var sdl_input_system = try allocator.create(sdl_input.SdlInputSystem);
        sdl_input_system.* = sdl_input.SdlInputSystem.new(allocator, input_system);

        if (sdl_input_system.keyboard) |*keyboard| {
            var game_context = sdl_input.SdlKeyboardContextBinding.default();
            var button_binding = sdl_input.SdlButtonBinding{
                .target = StringHash.new("Button1"),
            };
            game_context.button_bindings[c.SDL_SCANCODE_SPACE] = button_binding;
            keyboard.context_bindings.put(GameInputContext.name.hash, game_context) catch std.debug.panic("Hashmap put failed", .{});
        }

        var texture = SdlTexture.fromTexture(c.IMG_LoadTexture(sdl_renderer, "assets/some.png"));

        var font = c.TTF_OpenFont("assets/Kenney High.ttf", 100);
        var text_surface = c.TTF_RenderText_Solid(font, "This is some test text for Z-Pong!?!?!?", c.SDL_Color{ .r = 123, .g = 41, .b = 99, .a = 255 });
        defer c.SDL_FreeSurface(text_surface);
        var text_texture = SdlTexture.fromTexture(c.SDL_CreateTextureFromSurface(sdl_renderer, text_surface));

        return .{
            .should_quit = false,
            .allocator = allocator,

            .window = window,
            .sdl_renderer = sdl_renderer,

            .input_system = input_system,
            .sdl_input_system = sdl_input_system,

            .some_texture = texture,
            .some_font = font,
            .some_text_texture = text_texture,
        };
    }

    pub fn deinit(self: *Self) void {
        self.sdl_input_system.deinit();
        self.allocator.destroy(self.sdl_input_system);

        self.input_system.deinit();
        self.allocator.destroy(self.input_system);

        self.some_texture.deinit();
        self.some_text_texture.deinit();
        c.TTF_CloseFont(self.some_font);

        c.SDL_DestroyRenderer(self.sdl_renderer);
        c.SDL_DestroyWindow(self.window);

        log.info("Shutting Down SDL2", .{});
        c.TTF_Quit();
        c.IMG_Quit();
        c.SDL_Quit();
    }

    pub fn is_running(self: Self) bool {
        return !self.should_quit;
    }

    pub fn update(self: *Self) !void {
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            try self.sdl_input_system.proccess_event(&sdl_event);
            switch (sdl_event.type) {
                c.SDL_QUIT => self.should_quit = true,
                else => {},
            }
        }

        //Do game update logic
        //Do game render
        _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 255, 105, 97, 0);
        _ = c.SDL_RenderClear(self.sdl_renderer);

        //Preserve the aspect ratio of the background image
        {
            var screen_width_i: i32 = 0;
            var screen_height_i: i32 = 0;
            _ = c.SDL_GetRendererOutputSize(self.sdl_renderer, &screen_width_i, &screen_height_i);
            var screen_width = @intToFloat(f32, screen_width_i);
            var screen_height = @intToFloat(f32, screen_height_i);
            var texture_width = @intToFloat(f32, self.some_texture.width);
            var texture_height = @intToFloat(f32, self.some_texture.height);

            var screen_aspect_ratio = screen_width / screen_height;
            var texture_aspect_ratio = texture_width / texture_height;

            {
                var src_rect_ptr: ?*c.SDL_Rect = null;
                var src_rect: c.SDL_Rect = c.SDL_Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

                if (screen_aspect_ratio > texture_aspect_ratio) {
                    var new_height = texture_width / screen_aspect_ratio;
                    var new_offset = (texture_height - new_height) / 2.0;
                    src_rect.y = @floatToInt(i32, new_offset);
                    src_rect.w = self.some_texture.width;
                    src_rect.h = @floatToInt(i32, new_height);
                    src_rect_ptr = &src_rect;
                } else if (screen_aspect_ratio < texture_aspect_ratio) {
                    var new_width = screen_aspect_ratio * texture_height;
                    var new_offset = (texture_width - new_width) / 2.0;
                    src_rect.x = @floatToInt(i32, new_offset);
                    src_rect.w = @floatToInt(i32, new_width);
                    src_rect.h = self.some_texture.height;
                    src_rect_ptr = &src_rect;
                }

                _ = c.SDL_RenderCopy(self.sdl_renderer, self.some_texture.handle, src_rect_ptr, null);
            }
        }

        //Render Text
        {
            //TODO: Center Text on x axis
            var draw_area = c.SDL_Rect{
                .x = 0,
                .y = 0,
                .w = self.some_text_texture.width,
                .h = self.some_text_texture.height,
            };
            _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 0, 0, 0, 255);
            _ = c.SDL_RenderFillRect(self.sdl_renderer, &draw_area);
            _ = c.SDL_RenderCopy(self.sdl_renderer, self.some_text_texture.handle, null, &draw_area);
        }
        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }
};
