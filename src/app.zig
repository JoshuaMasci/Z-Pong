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

pub const LoadTextureError = error{
    SurfaceLoadFailed,
    CreateTextureFailed,
};
fn load_texture(renderer: *c.SDL_Renderer, file_path: [*c]const u8) LoadTextureError!*c.SDL_Texture {
    var loaded_surface = c.IMG_Load(file_path);
    if (loaded_surface == null) {
        return LoadTextureError.SurfaceLoadFailed;
    }
    defer c.SDL_FreeSurface(loaded_surface);

    if (c.SDL_CreateTextureFromSurface(renderer, loaded_surface)) |texture| {
        return texture;
    } else {
        return LoadTextureError.CreateTextureFailed;
    }
}

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    window: ?*c.SDL_Window,
    sdl_renderer: ?*c.SDL_Renderer,

    input_system: *input.InputSystem,
    sdl_input_system: *sdl_input.SdlInputSystem,

    some_texture: ?*c.SDL_Texture,

    pub fn init(allocator: std.mem.Allocator) !Self {
        log.info("Starting SDL2", .{});
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_JOYSTICK | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_HAPTIC) != 0) {
            std.debug.panic("SDL ERROR {s}", .{c.SDL_GetError()});
        }
        _ = c.IMG_Init(c.IMG_INIT_PNG);

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

        var texture = c.IMG_LoadTexture(sdl_renderer, "assets/some.png");
        return .{
            .should_quit = false,
            .allocator = allocator,

            .window = window,
            .sdl_renderer = sdl_renderer,

            .input_system = input_system,
            .sdl_input_system = sdl_input_system,

            .some_texture = texture,
        };
    }

    pub fn deinit(self: *Self) void {
        self.sdl_input_system.deinit();
        self.allocator.destroy(self.sdl_input_system);

        self.input_system.deinit();
        self.allocator.destroy(self.input_system);

        c.SDL_DestroyTexture(self.some_texture);
        c.SDL_DestroyRenderer(self.sdl_renderer);
        c.SDL_DestroyWindow(self.window);

        log.info("Shutting Down SDL2", .{});
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
        if (self.some_texture) |texture| {
            _ = c.SDL_RenderCopy(self.sdl_renderer, texture, null, null);
        }
        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }
};
