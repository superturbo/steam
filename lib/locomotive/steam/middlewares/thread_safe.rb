require 'json'

module Locomotive::Steam::Middlewares

  class ThreadSafe

    attr_accessor_initialize :app
    attr_accessor :env

    def call(env)
      threadsafed = dup
      threadsafed.env = env

      threadsafed._call # thread-safe purpose

      threadsafed.next
    end

    def next
      # avoid to be called twice
      @next_response || (@next_response = app.call(env))
    end

    #= Shortcuts =

    def services
      @services ||= env.fetch('steam.services')
    end

    def repositories
      @repositories ||= services.repositories
    end

    def request
      @request ||= env.fetch('steam.request')
    end

    def site
      @site ||= env.fetch('steam.site')
    end

    def page
      @page ||= env.fetch('steam.page')
    end

    def path
      @path ||= env.fetch('steam.path')
    end

    def locale
      @locale ||= env.fetch('steam.locale')
    end

    def locales
      site.locales
    end

    def default_locale
      site.default_locale
    end

    def params
      @params ||= request.GET.merge(body_params).merge(env['steam.route_params'] || {}).with_indifferent_access
    end

    # The fields of the request body, without the query string.
    def body_params
      json_request? ? (json_body || {}) : request.POST
    end

    def json_request?
      request.media_type == 'application/json' && (request.post? || request.put?)
    end

    def json_body
      return @json_body if defined?(@json_body)

      @json_body = read_json_body
    end

    # Empty bodies have no value. A JSON value other than an object goes under _json.
    # Do not retain parser errors because their messages can include the body.
    def read_json_body
      return unless (body = request.body)

      body.rewind
      return if (data = body.read).empty?

      data = JSON.parse(data)
      data.is_a?(Hash) ? data : { '_json' => data }
    rescue JSON::ParserError
      raise Locomotive::Steam::InvalidJsonBody, cause: nil
    end

    def merge_route_params(values)
      env['steam.route_params'] = (env['steam.route_params'] || {}).merge(values)
      @params = nil
    end

    def session
      env['rack.session']
    end

    def liquid_assigns
      @liquid_assigns ||= env.fetch('steam.liquid_assigns')
    end

    def live_editing?
      !!env['steam.live_editing']
    end

    def decorate_entry(entry)
      return nil if entry.nil?
      Locomotive::Steam::Decorators::I18nDecorator.new(entry, locale, default_locale)
    end

    def default_liquid_context
      ::Liquid::Context.new({ 'site' => site.to_liquid }, {}, {
        request:        request,
        locale:         locale,
        site:           site,
        services:       services,
        repositories:   services.repositories
      }, true)
    end

  end

end
