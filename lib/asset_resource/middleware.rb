require "asset_resource"

class AssetResource::Middleware

  attr_reader :app, :options

  def initialize(app, options={})
    @app = app
    @options = options

    if options[:handlers] then
      options[:handlers].each do |handler, mime_type|
        handle handler.to_sym, mime_type
      end
    else
      handle :scripts, "text/javascript"
      handle :styles,  "text/css"
    end

    if options[:filetypes] then
      options[:filetypes].each do |type, file_type|
        filetype type.to_sym, file_type
      end
    else
      filetype :scripts, "js"
      filetype :styles,  "css"
    end

    puts handlers.inspect
    puts filetypes.inspect

    translator :less do |filename|
      begin
        require "less"
        Less::Engine.new(File.read(filename)).to_css
      rescue LoadError
        raise "Tried to translate a less file but could not find the library.\nTry adding this to your Gemfile:\n  gem \"less\""
      end
    end

    translator :sass do |filename|
      begin
        require "sass"
        Sass::Engine.new(File.read(filename), :load_paths => [File.dirname(filename)]).render
      rescue LoadError
        raise "Tried to translate a sass file but could not find the library.\nTry adding this to your Gemfile:\n  gem \"haml\""
      end
    end
  end

  def call(env)
    if env["PATH_INFO"] =~ %r{\A/assets/(.+)}
      asset = $1
      fileprefix, filetype = asset.split(".")
      puts "asset: #{asset}"
      puts "fileprefix: #{fileprefix}"
      puts "type: #{filetype}"
      files = nil

      if handles?(fileprefix)
        files = files_for(fileprefix)
      end
      files = find_filename(asset)

      puts "files: #{files}"

      if files
        return [200, asset_headers(fileprefix), process_files(files)]
      end

      return app.call(env)
    end

    app.call(env)
  end

private ######################################################################

  def asset_headers(type)
    headers = options[:asset_headers] || { "Cache-Control" => "public, max-age=86400" }
    headers.merge("Content-Type" => handlers[type.to_sym])
  end

  def base_path
    options[:base_path] || "public"
  end

  def find_filename(filename)
    type = filetypes.invert[filename.split('.').last].to_s
    puts "find_filename path: #{File.expand_path(File.join(base_path, type, "**", "*"))}"
    Dir.glob(File.expand_path(File.join(base_path, type, "**", "*"))).select do |file|
      puts "file: #{file.split('/').last}"
      file.split('/').last == filename && File.exist?(file)
    end
  end

  def files_for(type)
    puts "files_for path: #{File.expand_path(File.join(base_path, type, "**", "*"))}"
    Dir.glob(File.expand_path(File.join(base_path, type, "**", "*"))).select do |file|
      File.exist?(file)
    end
  end

  def process_files(files)
    data = files.inject("") do |accum, file|
      ext = File.extname(file)[1..-1]
      accum << translator(ext).call(file)
    end
    StringIO.new(data)
  end

  def handlers
    @handler ||= {}
  end

  def filetypes
    @filetypes ||= {}
  end

  def handles?(type)
    handlers.keys.include?(type.to_sym)
  end

  def handles_filetype?(type)
    filetypes.values.include?(type.to_sym)
  end

  def handle(type, mime_type)
    handlers[type.to_sym] = mime_type
  end

  def filetype(type, file_type)
    filetypes[type.to_sym] = file_type
  end

  def default_translator
    lambda { |filename| File.read(filename) }
  end

  def translators
    @translators ||= Hash.new(default_translator)
  end

  def translator(type, &block)
    translators[type.to_sym] = block if block_given?
    translators[type.to_sym]
  end

end
