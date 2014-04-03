#!/usr/bin/env ruby

require "rubygems"
require "rubygame"
require "./ogmo"

class Wall
    include Rubygame::Sprites::Sprite
    def initialize(position, size)
        super()
        @rect = Rubygame::Rect.new(position, size)
    end
    def draw(target)
        target.fill([255,0,0], @rect)
    end
end

class Entity
    include Rubygame::Sprites::Sprite
    def initialize(position, size, top_left, surface)
        super()
        @image = surface
        @rect = Rubygame::Rect.new(position, size)
        @top_left = top_left
    end
    def update(dt)
    end
    def bump
    end
    def draw(screen)
        @image.blit(screen, [@rect.x+@top_left[0], @rect.y+@top_left[1]])
    end
end

class Loot < Entity
    attr_writer :spawned
    attr_reader :type
    def initialize(position, size, top_left, surface, drop, collect, type)
        super(position, size, top_left, surface)
        @base = @rect.y
        @rect.move!(0, -8)
        @dy = 160
        @ready = false
        @drop, @collect = drop, collect
        @type = type
        @spawned = false
    end
    def ready?
        @ready
    end
    def spawned?
        @spawned
    end
    def update(dt)
        @dy += 1000 * dt
        @rect.move!(0, @dy * dt)
        if @rect.y > @base
            @rect.y = @base
            @dy = -0.7 * @dy
            @drop.play unless @ready
            @ready = true
        end
    end
    def touch(other)
        return (other.rect.cx - @rect.cx).abs < 24 && (other.rect.cy - @rect.cy).abs < 24
    end
    def bump(player)
        return unless @ready
        return unless (player.rect.cx - @rect.cx).abs < 24
        return unless (player.rect.cy - @rect.cy).abs < 24
        player.collect(self)
        @collect.play
        kill
    end
end

class Player < Entity
    attr_writer :joyx, :joyy, :move
    attr_reader :maxx, :maxy, :block, :sync
    SPEED = 375.0 # pixels-per-second
    SIZE = 64
    MAX = 704
    BOUNCE = true
    def initialize(position, size, top_left, surface, walls, game)
        super(position, size, top_left, surface)
        @image = surface
        @frame = Rubygame::Rect.new(SIZE, SIZE, SIZE, SIZE)
        @dist = 0
        @joyx = 0.0
        @joyy = 0.0
        @maxx = 0.0
        @maxy = 0.0
        @sync = true
        @sync_rect = Rubygame::Rect.new_from_object(@rect)
        @snap_rect = Rubygame::Rect.new_from_object(@rect)
        @direction = [1,0]
        @debt = 0.0
        @walls = walls
        @block = [false, false, false, false]
        @game = game
        @move = false
        _updateSnap
    end
    def update(dt)
        dx, dy = _calculateDelta(dt)
        dx, dy = _changeDirection(dx, dy)
        dx, dy = _collideWithWalls(dx, dy)
        _updatePosition(dx, dy)
        _updateFrame(dx, dy)
    end
    def draw(target)
        #target.fill([0,0,255], @sync_rect)
        #target.fill([255,255,0], @snap_rect)
        image = @image
        image = image.flip(true, false) if @direction[0] > 0
        image.blit(target, [@rect.x+@top_left[0],@rect.y+@top_left[1]], @frame)
        image.blit(target, [@rect.x - MAX+@top_left[0], @rect.y+@top_left[1]], @frame) if @rect.x >= MAX - SIZE
        image.blit(target, [@rect.x+@top_left[0], @rect.y - MAX+@top_left[1]], @frame) if @rect.y >= MAX - SIZE
        image.blit(target, [@rect.x - MAX+@top_left[0], @rect.y - MAX+@top_left[1]], @frame) if @rect.x >= MAX - SIZE && @rect.y >= MAX - SIZE
    end
    def collect(item)
        @game.collect(item)
    end
  private
    def _calculateDelta(dt)
        return 0, 0 unless @move
        dx = @direction[0] * SPEED * dt
        dy = @direction[1] * SPEED * dt
        @debt += (dx - dx.to_i).abs
        @debt += (dy - dy.to_i).abs
        if @debt > 0.5 && (@direction[0].abs + @direction[1].abs == 1)
            dx += @direction[0]
            dy += @direction[1]
            @debt -= 1
        end
        return dx.to_i, dy.to_i
    end
    def _changeDirection(dx, dy)
        if @joyx.abs > 0.4 && @joyx.abs > @maxx.abs
            @maxx = @joyx
        end
        if @joyy.abs > 0.4 && @joyy.abs > @maxy.abs
            @maxy = @joyy
        end
        return dx, dy unless @sync || !@move || dx == 0 && dy == 0
        if @joyx.abs > 0.4 || @joyy.abs > 0.4
            @maxx = @joyx
            @maxy = @joyy
        end
        if @maxx.abs > 0.4 && @maxy.abs <= @maxx.abs && (dx == 0 && dy == 0 || @maxx > 0 && !@block[3] || @maxx < 0 && !@block[2])
            @direction = [@maxx <=> 0.0, 0]
            dx, dy = _snapToGrid(dx, dy)
            @maxx = 0.0
        elsif @maxy.abs > 0.4 && @maxx.abs <= @maxy.abs && (dx == 0 && dy == 0 || @maxy > 0 && !@block[1] || @maxy < 0 && !@block[0])
            @direction = [0, @maxy <=> 0.0]
            dx, dy = _snapToGrid(dx, dy)
            @maxy = 0.0
        end
        return dx, dy
    end
    def _snapToGrid(dx, dy)
        return 0, 0 unless @move
        if @direction[0] != 0
            correcty = @snap_rect.y - @rect.y
            @debt += dy - correcty
            dy = correcty
        elsif @direction[1] != 0
            correctx = @snap_rect.x - @rect.x
            @debt += dx - correctx
            dx = correctx
        end
        return dx, dy
    end
    def _updatePosition(dx, dy)
        _updateSnap unless @move
        return unless @move
        @rect.move!(dx, dy)
        @rect.x -= MAX if @rect.x >= MAX
        @rect.x += MAX if @rect.x < 0
        @rect.y -= MAX if @rect.y >= MAX
        @rect.y += MAX if @rect.y < 0
        x = SIZE * (@rect.x / SIZE)
        y = SIZE * (@rect.y / SIZE)
        @sync = @sync_rect.x != x || @sync_rect.y != y
        if @sync
            @sync_rect.x = x
            @sync_rect.y = y
        else
            _updateSnap
        end
    end
    def _updateSnap
        @snap_rect.x = @sync_rect.x
        @snap_rect.y = @sync_rect.y
        @snap_rect.x += SIZE if @direction[0] > 0
        @snap_rect.y += SIZE if @direction[1] > 0
    end
    def _collideWithWalls(dx, dy)
        @block[0] = false
        @block[1] = false
        @block[2] = false
        @block[3] = false
        collide_group(@walls).each do |wall|
            if @direction[0] == 1 && wall.rect.top <= @rect.top && wall.rect.bottom >= @rect.bottom && wall.rect.left <= @rect.right && wall.rect.right >= @rect.right
                @debt += @rect.right - wall.rect.left - 1
                @rect.right = wall.rect.left - 1
                @direction[0] = BOUNCE ? -1 : 0
                dx = -dx
                @rect.x += 1
                @debt += 1
                dx, dy = _snapToGrid(dx, dy)
            elsif @direction[0] == -1 && wall.rect.top <= @rect.top && wall.rect.bottom >= @rect.bottom && wall.rect.right >= @rect.left && wall.rect.left <= @rect.left
                @debt += wall.rect.right - @rect.left - 1
                @rect.left = wall.rect.right + 1
                @direction[0] = BOUNCE ? 1 : 0
                dx = -dx
                @rect.x -= 1
                @debt += 1
                dx, dy = _snapToGrid(dx, dy)
            elsif @direction[1] == 1 && wall.rect.left <= @rect.left && wall.rect.right >= @rect.right && wall.rect.top <= @rect.bottom && wall.rect.bottom >= @rect.bottom
                @debt += @rect.bottom - wall.rect.top - 1
                @rect.bottom = wall.rect.top - 1
                @direction[1] = BOUNCE ? -1 : 0
                dy = -dy
                @rect.y += 1
                @debt += 1
                dx, dy = _snapToGrid(dx, dy)
            elsif @direction[1] == -1 && wall.rect.left <= @rect.left && wall.rect.right >= @rect.right && wall.rect.bottom >= @rect.top && wall.rect.top <= @rect.top
                @debt += wall.rect.bottom - @rect.top - 1
                @rect.top = wall.rect.bottom + 1
                @direction[1] = BOUNCE ? 1 : 0
                dy = -dy
                @rect.y -= 1
                @debt += 1
                dx, dy = _snapToGrid(dx, dy)
            end
            @block[0] ||= wall.rect.left < @rect.right && wall.rect.right > @rect.left && wall.rect.bottom == @rect.top && wall.rect.top <= @rect.top
            @block[1] ||= wall.rect.left < @rect.right && wall.rect.right > @rect.left && wall.rect.top == @rect.bottom && wall.rect.bottom >= @rect.bottom
            @block[2] ||= wall.rect.top < @rect.bottom && wall.rect.bottom > @rect.top && wall.rect.right == @rect.left && wall.rect.left <= @rect.left
            @block[3] ||= wall.rect.top < @rect.bottom && wall.rect.bottom > @rect.top && wall.rect.left == @rect.right && wall.rect.right >= @rect.right
        end
        return dx, dy
    end
    def _updateFrame(dx, dy)
        @dist += (dx.abs + dy.abs)
        if @dist >= 16
            @frame.x += SIZE
            @frame.x = 0 if @frame.x > SIZE * 3
            @dist -= 16
        end
        if @direction[0] != 0
            @frame.y = SIZE * 2
        else
            @frame.y = 0 if @direction[1] < 0
            @frame.y = SIZE if @direction[1] > 0
        end
    end
end

class Game
    include Rubygame::EventHandler::HasEventHandler
    START =  19.75
    def initialize(framerate, path, full)
        Rubygame.init
        Rubygame::Joystick.activate_all

        @ogmo = Ogmo::Project.new(path)
        @ogmo.load

        @surfaces = {}
        @entities = Rubygame::Sprites::Group.new
        @loot = []
        @loot_count = {}
        @spawning = []
        @walls = Rubygame::Sprites::Group.new
        @player = nil

        @ogmo.tilesets.each do |tileset|
            _loadSurface(path, tileset.image)
        end
        @ogmo.objects.each do |object|
            _loadSurface(path, object.image)
        end

        sound_path = File.join(File.dirname(__FILE__), "assets")
        @drop = Rubygame::Sound.load(File.join(sound_path, "drop.wav"))
        @collect = Rubygame::Sound.load(File.join(sound_path, "collect.wav"))
        @collect.volume = 0.2
        @drop.volume = 0.1

        @music = Rubygame::Music.load(File.join(sound_path, "sanxion.mp3"))
        @music.volume = 0.3

        @width = full ? Rubygame::Screen.get_resolution[0] : @ogmo.settings.maxWidth * 2
        @height = full ? Rubygame::Screen.get_resolution[1] : @ogmo.settings.maxHeight * 2

        @screen = Rubygame::Screen.new([@width, @height], 0, Rubygame::HWSURFACE | Rubygame::DOUBLEBUF | (full ? Rubygame::FULLSCREEN : 0))
        @screen.title = @ogmo.name

        @background = Rubygame::Surface.new(@screen.size)
        @background.fill([25,50,100])

        Rubygame::TTF.setup
        ttfont_path = File.join(File.dirname(__FILE__), "assets", "FreeSans.ttf")
        @font = Rubygame::TTF.new( ttfont_path, 18 )

        @queue = Rubygame::EventQueue.new
        @queue.enable_new_style_events

        make_magic_hooks({
            escape: :_quit,
            q: :_quit,
            space: proc { @beat = true },
            left: :_prev,
            right: :_next,
            _joyaxis(0) =>  proc { |owner, event| @player.joyx = event.value },
            _joyaxis(1) =>  proc { |owner, event| @player.joyy = event.value },
            Rubygame::Events::QuitRequested => :_quit,
            Rubygame::Events::InputFocusGained  => :_update_screen,
            Rubygame::Events::WindowUnminimized => :_update_screen,
            Rubygame::Events::WindowExposed     => :_update_screen
        })

        @clock = Rubygame::Clock.new
        @clock.target_framerate = framerate if framerate > 0
        @clock.enable_tick_events
        @clock.calibrate

        @index = 0

        @beat = false
        @beat_time = 0
        @beats = []

        @timer = 0
        @best = 9999.9

        _load_level
    end
    def go
        dt = 0
        catch(:quit) do
            loop do
                tick_event = @clock.tick
                dt += tick_event.seconds
                while dt > 0.02
                    _update(0.02)
                    dt -= 0.02
                end
                _render
                @screen.flip
            end
        end
        Rubygame.quit
    end
    def collect(item)
        @loot_count[item.type] -= 1
    end
  private
def _loadSurface(base, file)
        path = File.join(base, @ogmo.settings.workingDirectory, file)
        @surfaces[file] = Rubygame::Surface.load(path).zoom(2)
    end
    def _update(dt)
        if @beat
            @beats << @beat_time
            @beat_time = 0
            @beat = false
        end
        @player.move = @beat_time > START
        @timer += dt if @beat_time > START && @entities.length > 1
        @beat_time += dt
        @music.play unless @music.playing?
        @queue.fetch_sdl_events
        @queue.each { |event| handle(event) }
        @entities.update(dt)
        _spawn_loot(dt)
        @player.collide_group(@entities).each do |entity|
            entity.bump(@player) if entity != @player
        end
    end
    def _render
        @background.blit(@screen, [0,0])
        @screen.draw_box(@top_left, [@top_left[0] + @level.width * 2, @top_left[1] + @level.height * 2], [255,0,0])
        @screen.clip = @clip
        @entities.draw(@screen)
        _renderTiles(@screen, @level.layers[:foreground].data, @top_left)
        #_debugDraw
        @screen.clip = nil
        @font.render("%2.2f" % @clock.framerate, true, [250,250,250]).blit(@screen, [@width-60,7])
        @font.render("%06.1f" % @timer, true, [250,250,250]).blit(@screen, [@width-100,@height-120])
        @font.render("%06.1f" % @best, true, [250,250,250]).blit(@screen, [@width-100,@height-60])
        @screen.update
    end
    def _renderTiles(dest, data, top_left = [0, 0])
        return unless data
        source = Rubygame::Rect.new
        data.each do |tile|
            set = @ogmo.tilesets[tile.set]
            source.w, source.h = set.tileWidth * 2, set.tileHeight * 2
            source.x, source.y = tile.tx * 2, tile.ty * 2
            @surfaces[set.image].blit(dest, [top_left[0] + tile.x * 2, top_left[1] + tile.y * 2], source)
        end
    end
    def _renderObjects(dest, data, top_left = [0, 0])
        return unless data
        source = Rubygame::Rect.new
        source.x, source.y = 0, 0
        data.each do |sprite|
            object = @ogmo.objects[sprite.type]
            source.w, source.h = object.width * 2, object.height * 2
            @surfaces[object.image].blit(dest, [top_left[0] + sprite.x * 2, top_left[1] + sprite.y * 2], source)
        end
    end
    def _debugDraw
        @walls.draw(@screen)
        @font.render("UP", true, [250,250,250]).blit(@screen, [@width-60,30]) if @player.block[0]
        @font.render("DOWN", true, [250,250,250]).blit(@screen, [@width-60,60]) if @player.block[1]
        @font.render("LEFT", true, [250,250,250]).blit(@screen, [@width-60,90]) if @player.block[2]
        @font.render("RIGHT", true, [250,250,250]).blit(@screen, [@width-60,120]) if @player.block[3]
        @font.render("(#{@player.maxx}, #{@player.maxy})", true, [250,250,250]).blit(@screen, [60,7])
        @font.render("SYNC", true, [250,250,250]).blit(@screen, [60,30]) if @player.sync
        @font.render("(#{@player.rect.x}, #{@player.rect.y})", true, [250,250,250]).blit(@screen, [60,60])
    end
    def _quit
        throw :quit
    end
    def _update_screen
        @screen.update
    end
    def _next
        @index += 1
        @index = 0 if @index >= @ogmo.levels.length
        _load_level
    end
    def _prev
        @index -= 1
        @index = @ogmo.levels.length - 1 if @index < 0
        _load_level
    end
    def _load_level
        @best = @timer if @timer > 0 && @timer < @best
        @timer = 0
        @music.stop
        @beats.clear
        @beat = false
        @beat_time = 0
        @entities.clear
        @loot.clear
        @loot_count.clear
        @spawning.clear
        @level = @ogmo.levels[@index]
        @level.load
        @top_left = [(@width - @level.width * 2)/2, (@height - @level.height * 2)/2]
        _spawn_entities
        _spawn_walls
        @clip = Rubygame::Rect.new(@top_left, [@level.width * 2, @level.height * 2])
        _renderTiles(@background, @level.layers[:background].data, @top_left)
        _renderTiles(@background, @level.layers[:scenery].data, @top_left)
    end
    def _spawn_entities
        @loot << {}
        @level.layers.each do |layer|
            next unless layer.type == 'objects'
            next unless layer.data
            @loot << {} if @loot.last.length > 0
            layer.data.each do |instance|
                object = @ogmo.objects[instance.type]
                position = [instance.x * 2, instance.y * 2]
                size = [object.width * 2, object.height * 2]
                case instance.type
                    when 'player' then @player = Player.new(position, size, @top_left, @surfaces[object.image], @walls, self) ; @entities << @player
                    when 'door' then nil
                    when 'button' then nil
                    when 'key' then nil
                    when 'block' then nil
                    else @loot.last[instance.type] ||= []; @loot.last[instance.type] << Loot.new(position, size, @top_left, @surfaces[object.image], @drop, @collect, instance.type)
                end
            end
        end
    end
    def _spawn_walls
        @level.layers.each do |layer|
            next unless layer.type == 'grid'
            layer.data.each do |instance|
                position = [instance.x * 2, instance.y * 2]
                size = [instance.w * 2, instance.h * 2]
                @walls << Wall.new(position, size)
            end
        end
    end
    def _spawn_loot(dt)
        if @spawning.length > 0
            return unless ! @spawning.last.spawned? || @spawning.last.ready?
            @spawning.pop if @spawning.last.ready?
            if @spawning.length > 0
                @entities << @spawning.last
                @spawning.last.spawned = true
                return
            end
        end
        @loot.each do |loot|
            loot.each do |type, items|
                @loot_count[type] ||= 0
                next if @loot_count[type] > 0
                next unless items.all? { |item| _can_spawn(item) }
                @loot_count[type] = items.length
                items.each { |item| @spawning << item }
                @spawning.reverse!
                loot.delete(type)
                return
            end
        end
    end
    def _can_spawn(item)
        item.collide_group(@entities).each { |other| return false if item.touch(other) }
        true
    end
    def _joyaxis(id)
        return Rubygame::EventTriggers::AndTrigger.new(
            Rubygame::EventTriggers::InstanceOfTrigger.new(
                Rubygame::Events::JoystickAxisMoved),
                Rubygame::EventTriggers::AttrTrigger.new(:joystick_id => 0, :axis => id))
    end
end

Game.new(0, File.join(".", "levels"), true).go
