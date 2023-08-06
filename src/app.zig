const std = @import("std");
const log = std.log;
const c = @import("c.zig");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");
const ui = @import("ui.zig");

//Maybe shouldn't be in a ui file
const SdlTexture = ui.SdlTexture;

pub const GameInputContext = input.InputContext{
    .name = StringHash.new("Game"),
    .buttons = &[_]StringHash{StringHash.new("Button1")},
    .axes = &[_]StringHash{StringHash.new("Axis1")},
};

pub const GameInputCallback = struct {
    const Self = @This();

    button1_state: bool,
    axis1_value: f32,

    fn init() Self {
        return .{
            .button1_state = false,
            .axis1_value = 0.0,
        };
    }
    fn callback(self: *Self) input.InputContextCallback {
        return .{
            .ptr = self,
            .button_callback = trigger_button,
            .axis_callback = trigger_axis,
        };
    }

    fn trigger_button(self_ptr: *anyopaque, button: StringHash, state: input.ButtonState) void {
        const self = @as(*Self, @ptrCast(@alignCast(self_ptr)));

        log.info("Button Triggered {s} -> {}", .{ button.string, state });

        if (button.hash == StringHash.new("Button1").hash) {
            self.button1_state = state == input.ButtonState.Pressed;
        }
    }

    fn trigger_axis(self_ptr: *anyopaque, axis: StringHash, value: f32) void {
        const self = @as(*Self, @ptrCast(@alignCast(self_ptr)));

        //log.info("Axis Triggered {s} -> {d:.2}", .{ axis.string, value });

        if (axis.hash == GameInputContext.axes[0].hash) {
            self.axis1_value = value;
        }
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

    //Game Assets
    background_texture: SdlTexture,
    blue_paddle_texture: SdlTexture,

    some_font: ?*c.TTF_Font,
    title_widget: ui.TextWidget,
    text_widget: ui.TextWidget,

    //Game Data
    game_input_callback: *GameInputCallback,

    player_paddle_postion: [2]i32,

    const PaddleMoveSpeed = 100;
    const PaddleYPosMax = 300;

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

        var window = c.SDL_CreateWindow("Z-Pong", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 1920, 1080, c.SDL_WINDOW_ALLOW_HIGHDPI);
        c.SDL_SetWindowMinimumSize(window, 960, 540);

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

        var background_texture = SdlTexture.fromTexture(c.IMG_LoadTexture(sdl_renderer, "assets/background_orange.png").?);
        var blue_paddle_texture = SdlTexture.fromTexture(c.IMG_LoadTexture(sdl_renderer, "assets/paddle_blue.png").?);

        var font = c.TTF_OpenFont("assets/Kenney High.ttf", 100).?;
        var title_widget = ui.TextWidget.init(sdl_renderer, font, "This is some test text for Z-Pong!?!?!?", c.SDL_Color{ .r = 123, .g = 41, .b = 99, .a = 255 }, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        var text_widget = ui.TextWidget.init(sdl_renderer, font, "assets/Kenney High.ttf", c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 }, null);

        var game_input_callback = try allocator.create(GameInputCallback);
        game_input_callback.* = GameInputCallback.init();

        try input_system.add_callback(GameInputContext.name, game_input_callback.callback());

        return .{
            .should_quit = false,
            .allocator = allocator,

            .window = window,
            .sdl_renderer = sdl_renderer,

            .input_system = input_system,
            .sdl_input_system = sdl_input_system,

            .game_input_callback = game_input_callback,

            .background_texture = background_texture,
            .blue_paddle_texture = blue_paddle_texture,

            .some_font = font,
            .title_widget = title_widget,
            .text_widget = text_widget,

            .player_paddle_postion = .{ 0, 0 },
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self.game_input_callback);

        self.sdl_input_system.deinit();
        self.allocator.destroy(self.sdl_input_system);

        self.input_system.deinit();
        self.allocator.destroy(self.input_system);

        self.text_widget.deinit();
        self.title_widget.deinit();
        c.TTF_CloseFont(self.some_font);

        self.blue_paddle_texture.deinit();
        self.background_texture.deinit();

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

        var screen_width_i: i32 = 0;
        var screen_height_i: i32 = 0;
        _ = c.SDL_GetRendererOutputSize(self.sdl_renderer, &screen_width_i, &screen_height_i);

        var screen_center_x = screen_width_i >> 1;
        var screen_center_y = screen_height_i >> 1;

        //Preserve the aspect ratio of the background image
        {
            var screen_width = @as(f32, @floatFromInt(screen_width_i));
            var screen_height = @as(f32, @floatFromInt(screen_height_i));
            var texture_width = @as(f32, @floatFromInt(self.background_texture.width));
            var texture_height = @as(f32, @floatFromInt(self.background_texture.height));

            var screen_aspect_ratio = screen_width / screen_height;
            var texture_aspect_ratio = texture_width / texture_height;

            {
                var src_rect_ptr: ?*c.SDL_Rect = null;
                var src_rect: c.SDL_Rect = c.SDL_Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

                if (screen_aspect_ratio > texture_aspect_ratio) {
                    var new_height = texture_width / screen_aspect_ratio;
                    var new_offset = (texture_height - new_height) / 2.0;
                    src_rect.y = @as(i32, @intFromFloat(new_offset));
                    src_rect.w = self.background_texture.width;
                    src_rect.h = @as(i32, @intFromFloat(new_height));
                    src_rect_ptr = &src_rect;
                } else if (screen_aspect_ratio < texture_aspect_ratio) {
                    var new_width = screen_aspect_ratio * texture_height;
                    var new_offset = (texture_width - new_width) / 2.0;
                    src_rect.x = @as(i32, @intFromFloat(new_offset));
                    src_rect.w = @as(i32, @intFromFloat(new_width));
                    src_rect.h = self.background_texture.height;
                    src_rect_ptr = &src_rect;
                }

                _ = c.SDL_RenderCopy(self.sdl_renderer, self.background_texture.handle, src_rect_ptr, null);
            }
        }
        if (!self.game_input_callback.button1_state) {
            self.title_widget.draw(self.sdl_renderer.?, [2]i32{ screen_center_x, 0 }, 1.0, .Centered, .Positive);
        }
        self.text_widget.draw(self.sdl_renderer.?, [2]i32{ screen_center_x, screen_center_y }, 1.0, .Centered, .Centered);

        self.blue_paddle_texture.draw(
            self.sdl_renderer.?,
            [2]i32{ screen_center_x + self.player_paddle_postion[0], screen_center_y + self.player_paddle_postion[1] },
            1.0,
            .Centered,
            .Centered,
        );

        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }
};
