module Locomotive
  module Steam

    class AuthService

      RESET_TOKEN_LIFETIME  = 1 * 3600 # 1 hour in seconds
      RESET_PASSWORD_HANDLE = 'reset_password'
      LOOKUP_TYPES          = %i(string email).freeze

      attr_accessor_initialize :site, :entries, :email_service, [:page_finder, :url_builder, :public_origin]

      def find_authenticated_resource(type, id)
        entries.find(type, id)
      end

      # The Engine writes the entry without the block below, so the password is
      # checked before any write.
      def sign_up(options, context, request = nil)
        field    = password_field(options)
        password = field && sign_up_password(options, field)

        unless field && ContentEntry.storable_password?(password)
          return [:invalid_entry, refused_sign_up(options, field, password)]
        end

        entry = entries.create(options.type, options.entry) do |_entry|
          _entry.extend(ContentEntryAuth)
          _entry.password_field = field
        end

        if entry.errors.empty?
          notify(:signed_up, entry, request)
          context[options.type.singularize] = entry
          send_welcome_email(options, context, entry)
        end

        [entry.errors.empty? ? :entry_created : :invalid_entry, entry]
      end

      def sign_in(options, request)
        field = password_field(options)
        entry = field && find_account(options, lookup_field(options))

        if entry&.password_matches?(field, options.password)
          notify(:signed_in, entry, request)
          return [:signed_in, entry]
        end

        :wrong_credentials
      end

      def sign_out(entry, request)
        notify(:signed_out, entry, request)

        :signed_out
      end

      # options is an instance of the AuthOptions class
      def forgot_password(options, context)
        return :reset_password_unavailable unless (url = reset_password_url)

        field   = password_field(options)
        lookup  = reset_field(options)
        entry   = field && find_account(options, lookup)
        address = entry && address_of(entry, lookup)

        if address.nil?
          :"wrong_#{lookup ? lookup.name : 'email'}"
        else
          entries.update_decorated_entry(entry, {
            '_auth_reset_token'   => SecureRandom.hex,
            '_auth_reset_sent_at' => Time.zone.now.iso8601
          })

          context['reset_password_url'] = "#{url}?auth_reset_token=#{entry['_auth_reset_token']}"
          context[options.type.singularize] = entry

          send_reset_password_instructions(options, context, address)

          :"reset_#{field}_instructions_sent"
        end
      end

      def reset_password(options, request)
        field = password_field(options)

        return :invalid_token       if options.reset_token.blank? || field.nil?
        return :password_too_short  if options.password.to_s.size < ContentEntry::MIN_PASSWORD_LENGTH
        return :invalid_password    unless ContentEntry.storable_password?(options.password)

        entry = entries.all(options.type, '_auth_reset_token' => options.reset_token).first

        if entry
          sent_at = Time.parse(entry[:_auth_reset_sent_at]).to_i
          now = Time.zone.now.to_i - RESET_TOKEN_LIFETIME

          if sent_at >= now
            entries.update_decorated_entry(entry, {
              "#{field}_hash"       => BCrypt::Password.create(options.password),
              '_auth_reset_token'   => nil,
              '_auth_reset_sent_at' => nil
            })
            notify(:reset_password, entry, request)

            return [:"#{field}_reset", entry]
          end
        end

        :invalid_token
      end

      def notify(action, entry, request)
        ActiveSupport::Notifications.instrument("steam.auth.#{action}",
          site:     site,
          entry:    entry,
          locale:   entries.locale,
          request:  request
        )
      end

      private

      # Reset links use the site's origin and page, never the request's host or fields.
      def reset_password_url
        origin = public_origin.respond_to?(:call) ? public_origin.call(site) : public_origin
        return no_reset_password_url('no public origin') if origin.blank?
        return no_reset_password_url('an invalid or off-site public origin') unless site_origin?(origin)

        page = page_finder.by_handle(RESET_PASSWORD_HANDLE, false)
        return no_reset_password_url('no published reset_password page') unless reset_password_page?(page)

        path = url_builder._url_for(page)
        return no_reset_password_url('a reset_password page path that cannot carry the token') unless plain_path?(path)

        "#{origin}#{path}"
      end

      def site_origin?(origin)
        uri = URI.parse(origin.to_s)
        return false unless uri.is_a?(URI::HTTP)
        # URI#origin leaves out a default port, which the origin may write.
        return false unless [uri.origin, "#{uri.scheme}://#{uri.host}:#{uri.port}"].include?(origin)

        site.domains.any? { |domain| domain.casecmp?(uri.host) } && (uri.scheme == 'https' || !site.redirect_to_https)
      rescue URI::InvalidURIError
        false
      end

      def reset_password_page?(page)
        !page.nil? && page.published? && !page.redirect? && !page.templatized?
      end

      def plain_path?(path)
        path.match?(%r{\A/[^?#\s\x00-\x1F\x7F]*\z})
      end

      def no_reset_password_url(reason)
        Locomotive::Common::Logger.error "[Auth] No password reset link for the site #{site._id}: it has #{reason}"
        nil
      end

      # An auth type declares one password field; a visitor may name it, never another.
      def password_field(options)
        fields = entries.get_type(options.type)&.password_fields || []
        return unless fields.one?

        name = fields.first.name.to_sym
        name if options.password_field.nil? || options.password_field.to_sym == name
      end

      def lookup_field(options, types = LOOKUP_TYPES)
        field = entries.get_type(options.type)&.fields_by_name&.[](options.id_field)
        field if field && types.include?(field.type) && !field.localized?
      end

      def reset_field(options)
        field = lookup_field(options, %i(email))
        field if field&.unique?
      end

      # A value naming more than one account names none.
      def find_account(options, lookup)
        return unless lookup && nonempty_string?(options.id)

        accounts = entries.all(options.type, lookup.name => options.id)
        accounts.first if accounts.one?
      end

      def nonempty_string?(value)
        value.is_a?(String) && !value.empty?
      end

      # Mail goes to the stored address, not the submitted lookup value.
      def address_of(entry, field)
        address = field && entry[field.name]
        address if Locomotive::Steam.email_address?(address)
      end

      def sign_up_password(options, field)
        options.entry.with_indifferent_access[field] if options.entry.is_a?(Hash)
      end

      def refused_sign_up(options, field, password)
        entry = entries.build(options.type, options.entry)
        return unless entry

        name = field || (options.password_field || :password).to_sym

        if field && ContentEntry.blank_password?(password) && password.to_s.size < ContentEntry::MIN_PASSWORD_LENGTH
          entry.errors.add(name, :too_short, count: ContentEntry::MIN_PASSWORD_LENGTH)
        else
          entry.errors.add(name, :invalid)
        end

        entry
      end

      def send_welcome_email(options, context, entry)
        return if options.disable_email
        return unless (address = address_of(entry, lookup_field(options, %i(email))))

        send_email options, context, address, <<-EMAIL
Hi,
You've been successfully registered.
Thanks!
EMAIL
      end

      def send_reset_password_instructions(options, context, address)
        send_email options, context, address, <<-EMAIL
Hi,
To reset your password please follow the link below: #{context['reset_password_url']}.
Thanks!
EMAIL
      end

      def send_email(options, context, address, default_body)
        email_options = { from: options.from, to: address, subject: options.subject, smtp: options.smtp }

        if options.email_handle
          email_options[:page_handle] = options.email_handle
        else
          email_options[:body] = default_body
        end

        email_service.send_email(email_options, context)
      end

      # Module inject to the content entry to enable
      # related authentication methods.
      #
      module ContentEntryAuth

        attr_accessor :password_field

        # Sign-up asks for the confirmation a write may omit.
        def valid?
          super

          confirmation = :"#{password_field}_confirmation"

          if self[confirmation].nil?
            errors.add(confirmation, :confirmation, attribute: _label_of(password_field))
          end

          errors.empty?
        end

      end

    end

  end
end
