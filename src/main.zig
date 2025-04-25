const std = @import("std");
const build_options = @import("build_options");
const raylib = @import("raylib");
const raygui = @import("raygui");
const shapes = @import("shapes.zig").shapes;

const initial_window_width = 800;
const initial_window_height = 640;

const grid_cell_size = 32;

const grid_columns = 10;
const grid_rows = 20;

const gravity_interval = 500;
const manual_drop_interval = 25;
const fade_length = 200;

const Cell = ?struct {
    color: raylib.Color,
    faded: ?usize = null,
};

const Game = struct {
    paused: bool,
    cells: [grid_columns][grid_rows]Cell,
    piece_x: isize,
    piece_y: isize,
    piece_rot: u2,
    piece_shape: usize,
    internal_rng: std.Random.Pcg,
    last_gravity: usize,
    time: usize,

    fn new() Game {
        var game = Game{
            .paused = false,
            .cells = [_][grid_rows]Cell{[_]Cell{null} ** grid_rows} ** grid_columns,
            .piece_x = undefined,
            .piece_y = undefined,
            .piece_rot = undefined,
            .piece_shape = undefined,
            .internal_rng = std.Random.Pcg.init(@intCast(std.time.milliTimestamp())),
            .last_gravity = undefined,
            .time = 0,
        };

        game.newPiece();

        return game;
    }

    fn rng(game: *Game) std.Random {
        return game.internal_rng.random();
    }

    fn newPiece(game: *Game) void {
        game.piece_x = 3;
        game.piece_y = 16;
        game.piece_rot = 0;
        game.piece_shape = game.rng().uintLessThan(usize, 7);
        game.last_gravity = game.time;
    }

    fn rotatePiece(game: *Game) void {
        std.debug.assert(!game.colliding());
        game.piece_rot +%= 1;
        if (game.colliding()) {
            // TODO: Wall kicks
            game.piece_rot -%= 1;
        }
    }

    fn shiftPiece(game: *Game, shift: isize) void {
        std.debug.assert(!game.colliding());
        game.piece_x += shift;
        if (game.colliding()) {
            game.piece_x -= shift;
        }
    }

    fn lowerPiece(game: *Game) error{TopReached}!void {
        std.debug.assert(!game.colliding());
        game.piece_y -= 1;
        if (game.colliding()) {
            game.piece_y += 1;
            for (shapes[game.piece_shape].blocks[game.piece_rot]) |block| {
                const x = game.piece_x + block.x;
                const y = game.piece_y + block.y;
                std.debug.assert(game.cells[@intCast(x)][@intCast(y)] == null);
                game.cells[@intCast(x)][@intCast(y)] = .{ .color = shapes[game.piece_shape].color };
            }
            game.newPiece();
            if (game.colliding()) {
                return error.TopReached;
            }
        }
    }

    fn colliding(game: Game) bool {
        for (shapes[game.piece_shape].blocks[game.piece_rot]) |block| {
            const x = game.piece_x + block.x;
            const y = game.piece_y + block.y;
            if (x < 0 or x >= grid_columns) return true;
            if (y < 0 or x >= grid_rows) return true;
            if (game.cells[@intCast(x)][@intCast(y)]) |_| return true;
        }

        return false;
    }
};

const State = union(enum) {
    main_menu,
    game: Game,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state: State = .main_menu;

    raylib.setConfigFlags(.{ .window_resizable = true });
    raylib.initWindow(initial_window_width, initial_window_height, "tetris");
    defer raylib.closeWindow();

    raylib.setExitKey(.null);
    raylib.setTargetFPS(60);

    while (!raylib.windowShouldClose()) {
        const window_width = raylib.getScreenWidth();
        const window_height = raylib.getScreenHeight();

        switch (state) {
            .main_menu => {
                raylib.beginDrawing();
                defer raylib.endDrawing();

                raylib.clearBackground(.white);

                if (raylib.isKeyPressed(.enter) or raygui.button(
                    .{
                        .x = @as(f32, @floatFromInt(window_width - 120)) / 2,
                        .y = @as(f32, @floatFromInt(window_height - 30)) / 2,
                        .width = 120,
                        .height = 30,
                    },
                    "New game",
                )) {
                    state = .{ .game = .new() };
                }
            },
            .game => |*game| {
                if (!game.paused) {
                    game.time += @intFromFloat(raylib.getFrameTime() * 1000);

                    for (0..grid_rows) |row| {
                        if (game.cells[0][row] != null and game.cells[0][row].?.faded == null) {
                            var complete = true;
                            for (0..grid_columns) |col| {
                                if (game.cells[col][row] == null) complete = false;
                            }

                            if (complete) {
                                for (0..grid_columns) |col| {
                                    std.debug.assert(game.cells[col][row].?.faded == null);
                                    game.cells[col][row].?.faded = game.time;
                                }
                            }
                        } else if (game.cells[0][row] != null and game.cells[0][row].?.faded != null and game.time - game.cells[0][row].?.faded.? > fade_length) {
                            for (row..grid_rows - 1) |r| {
                                for (0..grid_columns) |col| {
                                    game.cells[col][r] = game.cells[col][r + 1];
                                }
                            }
                            for (0..grid_columns) |col| {
                                game.cells[col][grid_rows - 1] = null;
                            }
                        }
                    }

                    if (raylib.isKeyPressed(.up)) {
                        game.rotatePiece();
                    }
                    if (raylib.isKeyPressed(.left)) {
                        game.shiftPiece(-1);
                    }
                    if (raylib.isKeyPressed(.right)) {
                        game.shiftPiece(1);
                    }
                    if ((game.time - game.last_gravity > manual_drop_interval and raylib.isKeyDown(.down)) or
                        game.time - game.last_gravity > gravity_interval)
                    {
                        game.last_gravity = game.time;
                        game.lowerPiece() catch |err| switch (err) {
                            error.TopReached => {
                                state = .main_menu;
                                continue;
                            },
                        };
                    }
                }
                if (raylib.isKeyPressed(.escape)) {
                    game.paused = !game.paused;
                }

                std.debug.assert(!game.colliding());

                raylib.beginDrawing();
                defer raylib.endDrawing();

                raylib.clearBackground(.white);

                const grid_width = grid_columns * grid_cell_size;
                const grid_height = grid_rows * grid_cell_size;
                const grid_offset_x = @divFloor(window_width - grid_width, 2);
                const grid_offset_y = @divFloor(window_height - grid_height, 2);

                for (0..grid_columns) |column| {
                    for (0..grid_rows) |row| {
                        raylib.drawRectangleLines(
                            @intCast(grid_offset_x + @as(isize, @intCast(column * grid_cell_size))),
                            @intCast(grid_offset_y + @as(isize, @intCast((grid_rows - row - 1) * grid_cell_size))),
                            grid_cell_size,
                            grid_cell_size,
                            .light_gray,
                        );
                        if (game.cells[column][row]) |cell| {
                            const color = if (cell.faded) |f|
                                cell.color.brightness(@as(f32, @floatFromInt(game.time - f)) / @as(f32, @floatFromInt(fade_length)))
                            else
                                cell.color;

                            drawBlock(
                                grid_offset_x + @as(isize, @intCast(column * grid_cell_size)),
                                grid_offset_y + @as(isize, @intCast((grid_rows - row - 1) * grid_cell_size)),
                                grid_cell_size,
                                color,
                            );
                        }
                    }
                }
                for (shapes[game.piece_shape].blocks[game.piece_rot]) |block| {
                    drawBlock(
                        grid_offset_x + (game.piece_x + block.x) * grid_cell_size,
                        grid_offset_y + (grid_rows - game.piece_y - 1 - block.y) * grid_cell_size,
                        grid_cell_size,
                        shapes[game.piece_shape].color,
                    );
                }
                raylib.drawRectangleLines(@intCast(grid_offset_x - 1), @intCast(grid_offset_y - 1), @intCast(grid_width + 2), @intCast(grid_height + 2), .black);

                if (game.paused) {
                    raylib.drawRectangle(0, 0, window_width, window_height, raylib.Color.light_gray.alpha(0.75));
                    _ = raygui.panel(.{
                        .x = @as(f32, @floatFromInt(window_width - 200)) / 2,
                        .y = @as(f32, @floatFromInt(window_height - 300)) / 2,
                        .width = 200,
                        .height = 300,
                    }, null);
                    raylib.drawText(
                        "PAUSED",
                        @divFloor(window_width - raylib.measureText("PAUSED", 20), 2),
                        @divFloor(window_height - 300, 2) + 50,
                        20,
                        .gray,
                    );
                    if (raygui.button(.{
                        .x = @as(f32, @floatFromInt(window_width - 200)) / 2 + 40,
                        .y = @as(f32, @floatFromInt(window_height - 300)) / 2 + 150,
                        .width = 120,
                        .height = 30,
                    }, "Resume")) game.paused = false;
                    if (raygui.button(.{
                        .x = @as(f32, @floatFromInt(window_width - 200)) / 2 + 40,
                        .y = @as(f32, @floatFromInt(window_height - 300)) / 2 + 200,
                        .width = 120,
                        .height = 30,
                    }, "Quit")) state = .main_menu;
                }

                if (build_options.debug_info) {
                    const text = try std.fmt.allocPrintZ(
                        allocator,
                        \\FPS: {}
                    ,
                        .{
                            raylib.getFPS(),
                        },
                    );
                    defer allocator.free(text);
                    raylib.drawText(text, 10, 10, 20, .dark_green);
                }
            },
        }
    }
}

fn drawBlock(x: isize, y: isize, size: usize, color: raylib.Color) void {
    raylib.drawRectangle(@intCast(x), @intCast(y), @intCast(size), @intCast(size), color);
    raylib.drawRectangleLinesEx(
        .{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .width = @floatFromInt(size),
            .height = @floatFromInt(size),
        },
        @divFloor(@as(f32, @floatFromInt(size)), 8),
        color.brightness(-0.25),
    );
}
