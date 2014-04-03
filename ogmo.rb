#!/usr/bin/env ruby

require "rubygems"
require "nokogiri"

module Ogmo

    class Base
        def initialize
            @loaded = false
        end
        def load
            @loaded = true
        end
        def loaded?
            @loaded
        end
      private
        def _addData(collection, object)
            return unless object
            data = {}
            object.attributes.each do |key, value|
                next if key == 'name'
                key, value = key.to_sym, value.to_s
                data[key] = Integer(value) rescue ['true', 'false'].include?(value) ? value == 'true' : value
            end
            if values = _loadValues(object) then data[:values] = values end
            if nodes = object.search('nodes').first
                nodes['name'] = 'nodes'
                _addData(data, nodes)
            end
            collection << _toStruct(data) if collection.kind_of?(Array)
            collection[object['name'].to_sym] = _toStruct(data) if collection.kind_of?(Hash)
        end
        def _toStruct(collection)
            return nil if collection.length == 0
            Struct.new(*collection.keys).new(*collection.values)
        end
    end

    class Level < Base
        attr_reader :path, :values, :width, :height, :layers
        def initialize(project, path)
            super()
            @project, @path = project, path
        end
        def load
            return if @loaded
            path = File.join(@project.base, @path)
            raise "Cannot find OGMO level file '#{path}'" unless File.exist?(path)
            blob = File.open(path) { |file| file.read }
            doc = Nokogiri.XML(blob)
            @width = (search = doc.search('width').first) ? search.content.to_i : nil
            @height = (search = doc.search('height').first) ? search.content.to_i : nil
            @values = _loadValues(doc)
            @layers = _loadLayers(doc)
            super
        end
      private
        def _loadValues(doc)
            values = {}
            return nil unless search = doc.search('level').first
            search.attributes.each do |key, value|
                key, value = key.to_sym, value.to_s
                values[key] = case @project.values[key]
                    when 'string' then value.to_s
                    when 'text' then value.to_s
                    when 'integer' then value.to_i
                    when 'boolean' then value == 'true'
                    when 'number' then value.to_f
                    else raise "Unknown value '#{key}'"
                end
            end
            _toStruct(values)
        end
        def _loadLayers(doc)
            layers = {}
            @project.layers.each_pair do |name, layer|
                data = { type: layer.type, data: _loadLayer(doc, name, layer.type) }
                layers[name] = _toStruct(data)
            end
            _toStruct(layers)
        end
        def _loadLayer(doc, name, type)
            return nil unless search = doc.search(name).first
            case type
                when 'grid' then _loadGrid(search)
                when 'objects' then _loadObjects(search)
                when 'tiles' then _loadTiles(search)
                else raise "Unknown layer '#{type}'"
            end
        end
        def _loadGrid(doc)
            grid = []
            doc.children.each do |rect|
                next if rect.name != 'rect'
                _addData(grid, rect)
            end
            grid
        end
        def _loadObjects(doc)
            objects = []
            doc.children.each do |object|
                next unless @project.objects.members.include?(object.name.to_sym)
                objects << _loadObject(object)
            end
            objects
        end
        def _loadTiles(doc)
            tiles = []
            default = doc.attributes['set']
            doc.children.each do |tile|
                next if tile.name != 'tile'
                tile['set'] = default unless tile['set']
                _addData(tiles, tile)
            end
            tiles
        end
        def _loadObject(doc)
            object = {}
            object[:type] = doc.name
            values = @project.objects[doc.name].values
            doc.attributes.each do |key, value|
                key, value = key.to_sym, value.to_s
                if [:x,  :y, :width, :height].include?(key)
                    object[key] = value.to_i
                    next
                end
                object[:values] ||= {}
                object[:values][key] = case values[key]
                    when 'string' then value.to_s
                    when 'text' then value.to_s
                    when 'integer' then value.to_i
                    when 'boolean' then value == 'true'
                    when 'number' then value.to_f
                    else raise "Unknown value '#{key}'"
                end
            end
            doc.children.each do |node|
                next unless node.name == 'node'
                object[:nodes] ||= []
                _addData(object[:nodes], node)
            end
            _toStruct(object)
        end
    end

    class Project < Base
        attr_reader :base, :name, :settings, :values, :tilesets, :objects, :folders, :layers, :levels
        def initialize(base)
            super()
            @base = base
        end
        def load(project = nil)
            return if @loaded
            project = _findProject unless project
            path = File.join(@base, project)
            raise "Cannot find OGMO project file '#{path}'" unless File.exist?(path)
            blob = File.open(path) { |file| file.read }
            doc = Nokogiri.XML(blob)
            @name = (search = doc.search('name').first) ? search.content : nil
            @settings = _loadSettings(doc)
            @values = _loadValues(doc)
            @tilesets = _loadTilesets(doc)
            @objects = _loadObjects(doc)
            @folders = _loadFolders(doc)
            @layers = _loadLayers(doc)
            @levels = _loadLevels
            super()
        end
      private
        def _findProject
            Dir.new(@base).each do |file|
                return file if file =~ /\.oep$/
            end
        end
        def _loadSettings(doc)
            settings = {}
            return nil unless search = doc.search('settings').first
            search.children.each do |setting|
                next if setting.name == 'text'
                settings[setting.name.to_sym] = Integer(setting.content) rescue setting.content
            end
            settings[:defaultWidth] ||= 640
            settings[:defaultHeight] ||= 480
            settings[:maxWidth] ||= settings[:defaultWidth]
            settings[:maxHeight] ||= settings[:defaultHeight]
            settings[:minWidth] ||= settings[:defaultWidth]
            settings[:minHeight] ||= settings[:defaultHeight]
            _toStruct(settings)
        end
        def _loadValues(doc)
            values = {}
            return nil unless search = doc.search('values').first
            search.children.each do |value|
                next unless value['name']
                values[value['name'].to_sym] = value.name
            end
            _toStruct(values)
        end
        def _loadTilesets(doc)
            tilesets = {}
            return nil unless search = doc.search('tilesets').first
            search.children.each do |tileset|
                next unless tileset.name == 'tileset'
                _addData(tilesets, tileset)
            end
            _toStruct(tilesets)
        end
        def _loadObjects(doc)
            objects = {}
            doc.search('object').each do |object|
                _addData(objects, object)
            end
            _toStruct(objects)
        end
        def _loadFolders(doc)
            folders = {}
            doc.search('folder').each do |folder|
                data = {}
                folder.children.each do |object|
                    next if object.name == 'text'
                    _addData(data, object)
                end
                folders[folder['name'].to_sym] = _toStruct(data)
            end
            _toStruct(folders)
        end
        def _loadLayers(doc)
            layers = {}
            return nil unless search = doc.search('layers').first
            search.children.each do |layer|
                next unless ['grid', 'objects', 'tiles'].include?(layer.name)
                layer['type'] = layer.name
                _addData(layers, layer)
            end
            _toStruct(layers)
        end
        def _loadLevels
            files = []
            levels = {}
            Dir.new(@base).each do |file|
                files << Regexp.last_match(1) if file =~ /^([^ ]*)\.oel$/
            end
            files.sort.each do |name|
                levels[name.to_sym] = Level.new(self, "#{name}.oel")
            end
            _toStruct(levels)
        end
    end

end
