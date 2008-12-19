#!/usr/bin/env ruby

# == Synopsis
# This is a hack that will scan a database and create a mindmap of the tables and fields.
# It also will link foreign keys to primary keys, assuming naming convention of FK_* maps
# to PK_*.
#
# == Details
# This is designed to run on LinuxMCE 0710B2.  This environment has ruby but no extra
# gems.  So instead of using ActiveRecord for db, we simply shell mysql commands.
#
# == Usage
# ./mysql2mm.rb database_name1 [database_name2...]
#
# Example:
#
#   ./mysql2mm.rb pluto_media
#
# will read the structure of the pluto_media database and create a pluto_media.mm mind map
# in the current directory.
#
# == Author
# Roy Wright
#
# == Copyright
# Copyright (c) 2008 Roy Wright  All Rights Reserved.


require 'optparse'
#require 'rdoc/usage'
require 'yaml'
require 'rexml/document'
include REXML

# == Synopsis
# class to encapsulate querying the structure of the database
class DatabaseDescription

  def initialize(config, logger)
    @config = config
    @logger = logger
    @mysql = "mysql -u #{@config[:user]}"
    @mysql += " --password=#{@config[:password]}" unless @config[:password].nil?
  end

  # == Synopsis
  # does the given database name exist?
  def validDbName?(dbName)
    mysql("show databases;").split("\n").each do |line|
      line =~ /^Database\:\s+(\S+)/
      return true if $1 == dbName
    end
    return false
  end

  # == Synopsis
  # use the given database.  Must be called before querying structure.
  def use(dbName)
    @dbName = dbName
  end

  # == Synopsis
  # get the tables in the database currently in use.
  # return as an array of table names.
  def tables()
    t = []
    mysql("use #{@dbName};show tables;").split("\n").each do |line|
      t << $1 if line =~ /^\S+\:\s+(\S+)/
    end
    return t
  end

  # == Synopsis
  # get the description for the given table in the database currently in use.
  # return the description as an html string.
  def table_html(table)
    mysql("use #{@dbName};show columns from #{@dbName}.#{table};", '-H')
  end

  # == Synopsis
  # get the fields (columns) of the given table.
  # return an array of hashes with key = field name & value = field value
  def fields(table)
    fields = []
    attributes = nil
    mysql("use #{@dbName};show columns from #{@dbName}.#{table};").split("\n").each do |line|
#      p line
      if line =~ /^\*+/
        attributes = {}
        fields << attributes
      end
      attributes[$1] = $2 if line =~ /(\S+)\:\s+(\S+)/
    end
    return fields
  end

  private
  
  def mysql(cmd, mode='-E')
    @logger.puts "#{@mysql} -E -e \"#{cmd}\"" if $DEBUG
    `#{@mysql} #{mode} -e "#{cmd}"`
  end
end

# == Synopsis
# class used to generate unique random ID's like MindMap.
class ID
  def initialize
    @@used = {}
  end

  def to_s
    n = rand(2000000000)
    while !@@used[n].nil? do
      n = rand(2000000000)
    end
    @@used[n]=1
    return n
  end
end

# == Synopsis
# this is a helper class for creating MindMap node elements.
class MindMapNode
  KEY_ICON = 'password'
  PRI_ICON = 'full-1'
  UNIQUE_ICON = 'ksmiletris'
  AUTO_INCREMENT_ICON = 'wizard'

  def initialize(name, fields=nil)
    @name = name
    @fields = fields
    @children = []
  end

  def rootNode(isRootNode=false)
    @rootNode = isRootNode
  end

  # == Synopsis
  # add an html String as a note
  def addNote(note)
    @note = note
  end

  # == Synopsis
  # add an element as a child to the node element
  def addChild(child)
    @children << child
  end

  # == Synopsis
  # convert the MindMapNode to an REXML Element
  def to_element
    e = Element.new('node')
    e.add_attribute('CREATED', Time.now.to_i.to_s)
    e.add_attribute('FOLDED', "true") unless @rootNode
    e.add_attribute('ID', "Freemind_Link_#{ID.new.to_s}")
    e.add_attribute('MODIFIED', Time.now.to_i.to_s)
    e.add_attribute('POSITION', 'right') unless @rootNode
    if @rootNode
      name_element = Element.new('richcontent')
      name_element.add_attribute('TYPE', "NODE")
      str = '<html><head> </head><body><p align="center">' + @name + '</p></body></html>'
      html_doc = Document.new(str)
      name_element << html_doc.root
      e.add(name_element)
      font_element = Element.new('font')
      font_element.add_attribute('BOLD', "true")
      font_element.add_attribute('NAME', "Dialog")
      font_element.add_attribute('SIZE', "18")
      e.add(font_element);
    else
      e.add_attribute('TEXT', @name)
      font_element = Element.new('font')
      font_element.add_attribute('BOLD', "true")
      font_element.add_attribute('NAME', "SansSerif")
      font_element.add_attribute('SIZE', "12")
      e.add(font_element);
    end
    @children.each do |child|
      e.add(child)
    end
    if @name =~ /^EK_/
      font_element = Element.new('font')
      font_element.add_attribute('BOLD', 'true')
      font_element.add_attribute('NAME', 'SansSerif')
      font_element.add_attribute('SIZE', '12')
      e.add(font_element)
    end
    unless @description.nil?
      note_element = Element.new('richcontent')
      note_element.add_attribute('TYPE', 'NOTE')
      @description.gsub!(/BORDER=1/, 'BORDER="1"')
      str = '<html><head></head><body><p>' + @description + '</p></body></html>'
      html_doc = Document.new(str)
      note_element << html_doc.root
      e.add(note_element)
    end
    unless @note.nil?
      note_element = Element.new('richcontent')
      note_element.add_attribute('TYPE', 'NOTE')
      @note.gsub!(/BORDER=1/, 'BORDER="1"')
      str = '<html><head></head><body><p>' + @note + '</p></body></html>'
      html_doc = Document.new(str)
      note_element << html_doc.root
      e.add(note_element)
    end
    unless @fields.nil?
      unless @fields['Key'].nil? || @fields['Key'].empty?
        addIcon(e, PRI_ICON) if @fields['Key'] == 'PRI'
        addIcon(e, UNIQUE_ICON) if @fields['Key'] == 'UNI'
        addIcon(e, KEY_ICON)
      end
      unless @fields['Extra'].nil? || @fields['Extra'].empty?
        addIcon(e, AUTO_INCREMENT_ICON) if @fields['Extra'] == 'auto_increment'
      end
    end
    return e
  end

  def addIcon(e, type)
    icon_element = Element.new('icon')
    icon_element.add_attribute('BUILTIN', type)
    e.add(icon_element)
  end

end

# == Synopsis
# Helper class for generating arrowlink Elements
class ArrorLink
  def initialize(dest_id, color)
    @dest_id = dest_id
    @color = color
  end

  def to_element()
    e = Element.new('arrowlink')
    e.add_attribute('COLOR', @color)
    e.add_attribute('DESTINATION', @dest_id)
    e.add_attribute('ENDARROW', 'Default')
    e.add_attribute('ENDINCLINATION', '500;0;')
    e.add_attribute('ID', "Freemind_Arrow_Link_#{ID.new.to_s}")
    e.add_attribute('STARTARROW', 'None')
    e.add_attribute('STARTINCLINATION', '500;0;')
    return e
  end
end

# == Synopsis
# Helper class for varying the color of the arrow links
class Color
  # avoid too dark and too light
  MIN_COLOR = 0x202020
  MAX_COLOR = 0xd0d0d0
  def initialize(divisions)
    @incr = ((MAX_COLOR - MIN_COLOR) / divisions).to_i
    @current_color = MIN_COLOR
  end

  def to_s
    sprintf("#%6.6x", @current_color)
  end

  def increment
    @current_color += @incr
    @current_color = MAX_COLOR if @current_color > MAX_COLOR
  end
end

# == Synopsis
# Main class used to create the MindMap from the database
class MindMap
  def initialize(config, logger, dbName)
    @config = config
    @logger = logger
    @dbName = dbName
  end

  # == Synopsis
  # create the mind map
  # == Details
  # examines the DB and creates the .mm xml file on the fly
  # to minimize memory usage.
  def create()
    dd = DatabaseDescription.new(@config, @logger)
    if dd.validDbName?(@dbName)
      @logger.puts "Valid database name: #{@dbName}, processing..."
      dd.use(@dbName)
      xml = Document.new
      xml << XMLDecl.default
      rootElement = Element.new('map')
      rootElement.add_attribute('version', '0.9.0_Beta_8')
      xml << rootElement
      topNode = MindMapNode.new(@dbName)
      topNode.rootNode(true)
      topElement = topNode.to_element
      rootElement << topElement
      dd.tables.each do |table|
        unless table =~ /^psc_/
          tableNode = MindMapNode.new(table)
          fields = dd.fields(table)
#          p fields
          fields.each do |child|
            unless child['Field'].nil?
              unless child['Field'] =~ /^psc_/
#		p child['Key'] unless child['Key'].nil? || child['Key'].empty?
                fieldNode = MindMapNode.new(child['Field'], child)
                tableNode.addChild(fieldNode.to_element)
              end
            end
          end
          tableNode.addNote(dd.table_html(table))
          topElement << tableNode.to_element
        end
      end
      addLinks(xml)
#      xml.write(File.new("#{@dbName}.mm", "w"), 0)
      str = StringIO.new("", "w")
      xml.write(str, 2)
      File.open("#{@dbName}.mm", "w") do |file|
        file.print(str.string.gsub!(/(<richcontent.*?>)\s+(<html>)/, '\1\2'))
      end
    else
      @logger.puts "Not a valid database name: #{@dbName}"
    end
  end

  private

  # == Synopsis
  # add the arrow links to FK_* Elements that reference corresponding
  # PK_* Elements
  def addLinks(xml)
    pks = {}
    fks = {}
    xml.root.elements.each('//node') do |element|
      value = element.attributes['TEXT']
      unless value.nil?
        pks[value] = element if value.=~ /^PK_/
        if value =~ /^[EF]K_/
          fks[value] ||= []
          fks[value] << element
        end
      end
    end
    color = Color.new(pks.length)
    fks.each do |fk, elements|
      unless elements.nil?
        pk = fk.gsub(/^[EF]K_/, 'PK_')
        pk_element = pks[pk]
        unless pk_element.nil?
          dest_id = pk_element.attributes['ID']
          unless dest_id.nil?
            elements.each do |fk_element|
              fk_element.add(ArrorLink.new(dest_id, color.to_s).to_element)
            end
          end
        end
        color.increment
      end
    end
  end
end


# running this file from the command line?
if __FILE__ == $0

  # == Synopsis
  # command line exit codes
  class ExitCode
    UNKNOWN = 3
    CRITICAL = 2
    WARNING = 1
    OK = 0
  end

  # == Synopsis
  # bare bones logger
  # == Usage
  # logger = Logger.new(STDOUT)
  # logger.debug("...")
  # logger.puts("...")
  # logger.error("...")
  class Logger
    def initialize(outputter)
      @outputter = outputter
    end
    def puts(str)
      @outputter.puts(str)
    end
    def debug(str)
      @outputter.puts(str) if $DEBUG
    end
    def error(str)
      @outputter.puts("ERROR: #{str}")
    end
  end


  module Runner

    def self.run(args)
      @logger = Logger.new(STDOUT)

      # load config values from defaultConfig(), then ~/.mysql2mm, then .mysql2mm
      configFile = ".mysql2mm"
      homeConfigFile = File.join("#{ENV['HOME']}", configFile)
      @config = defaultConfig()
      @config.merge(YAML.load_file(homeConfigFile)) if File.exist?(homeConfigFile)
      @config.merge(YAML.load_file(configFile)) if File.exist?(configFile)

      p @config if $DEBUG

      # parse the command line
      options = setupParser()
      rest = options.parse(*args)

      # create and execute class instance here

      # for each database name given on the command line
      rest.each do |dbName|
        mm = MindMap.new(@config, @logger, dbName)
        mm.create
      end
    end

    # == Synopsis
    # default configuration values
    def self.defaultConfig()
      config = {}
      config['base_dir'] = File.expand_path('.')
      config[:user] = 'root'
      config[:password] = nil
      return config
    end

    # == Synopsis
    # setup the command line option parser
    def self.setupParser()
      options = OptionParser.new
      options.on_tail("-h", "--help", "This usage information") {|val| usage(options)}
      options.on("-p PASSWORD", String, "Database Password (no password is the default)") do |val|
        @config[:password]=val
      end
      options.on("-u USER", String, "Database User (root is the default)") do |val|
        @config[:user]=val
      end
      return options
    end

    # == Synopsis
    # print the usage message
    def self.usage(*objects)
      #RDoc::usage_no_exit('Synopsis', 'Copyright')
      @logger.puts 'Create a mindmap from a mysql database.'
      @logger.puts 'Usage: mysql2mm.rb [options] db_name1 [db_name2...]'
      @logger.puts 'Options:'
      objects.each do |obj|
        @logger.puts obj.to_s
      end
      exit ExitCode::UNKNOWN
    end

  end
  Runner.run(ARGV)
end

