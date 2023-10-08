require 'fileutils'

class ApplicationLogger < Rack::CommonLogger
  def self._logger
    return @_logger if @_logger

    environment = ENV['RACK_LOGGER_FILENAME'] || ENV['RACK_ENV'] || :development
    FileUtils.mkdir_p('log')
    file_logger = ActiveSupport::Logger.new("log/#{environment}.log")
    file_logger.formatter = ::Logger::Formatter.new
    # ref: https://github.com/rails/rails/blob/v7.0.7.2/railties/lib/rails/commands/server/server_command.rb#L78-L84
    unless ActiveSupport::Logger.logger_outputs_to?(file_logger, STDERR, STDOUT)
      console_logger = ActiveSupport::Logger.new(STDOUT)
      console_logger.formatter = ::Logger::Formatter.new
      file_logger.extend(ActiveSupport::Logger.broadcast(console_logger))
    end
    @_logger = ActiveSupport::TaggedLogging.new(file_logger)
  end

  module Helper
    def logger
      env['app.logger'] || env['rack.logger']
    end
  end

  def initialize(app, logger = nil)
    super(app, logger || ApplicationLogger._logger)
  end

  def call(env)
    if /\/ping/.match(env['PATH_INFO'])
      @logger.silence do
        @app.call(env)
      end
    else
      env['app.logger'] = @logger
      with_request_id_tagged_logging(env) do
        with_request_verbose_logging(env) do
          super(env)
        end
      end
    end
  end

  private

  def with_request_id_tagged_logging(env)
    if @logger.respond_to?(:tagged)
      request_id = env['HTTP_X_REQUEST_ID'] ||= SecureRandom.uuid
      @logger.tagged(request_id) do
        yield.tap do |_, headers, _|
          headers['X-Request-Id'] = request_id
        end
      end
    else
      yield
    end
  end

  def with_request_verbose_logging(env)
    if @logger.respond_to?(:info)
      @logger.info("Started #{env['REQUEST_METHOD']} \"#{env['PATH_INFO']}\" for #{env['REMOTE_ADDR']}")
      params = Rack::Request.new(env).params
      @logger.info "  Parameters: #{params.inspect}" unless params.empty?
      yield.tap do |status, _, _|
        if (error = env['sinatra.error'])
          @logger.error("#{error}\n#{error.backtrace.join("\n")}")
        end
        @logger.info("Completed #{env['REQUEST_METHOD']} \"#{env['PATH_INFO']}\" for #{env['REMOTE_ADDR']} - #{status}")
      end
    else
      yield
    end
  end
end
