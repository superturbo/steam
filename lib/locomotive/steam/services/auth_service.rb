module Locomotive
  module Steam

    class AuthService

      RESET_TOKEN_LIFETIME  = 1 * 3600 # 1 hour in seconds

      attr_accessor_initialize :site, :entries, :email_service

      def find_authenticated_resource(type, id)
        entries.find(type, id)
      end

      # The Engine writes the entry without the block below, so the password is
      # checked before any write.
      def sign_up(options, context, request = nil)
        password = sign_up_password(options)

        return [:invalid_entry, refused_sign_up(options, password)] unless ContentEntry.storable_password?(password)

        entry = entries.create(options.type, options.entry) do |_entry|
          _entry.extend(ContentEntryAuth)
          _entry.password_field = options.password_field.to_sym
        end

        if entry.errors.empty?
          notify(:signed_up, entry, request)
          context[options.type.singularize] = entry
          send_welcome_email(options, context)
        end

        [entry.errors.empty? ? :entry_created : :invalid_entry, entry]
      end

      def sign_in(options, request)
        entry = entries.all(options.type, options.id_field => options.id).first

        if entry&.password_matches?(options.password_field, options.password)
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
        entry = entries.all(options.type, options.id_field => options.id).first

        if entry.nil?
          :"wrong_#{options.id_field}"
        else
          entries.update_decorated_entry(entry, {
            '_auth_reset_token'   => SecureRandom.hex,
            '_auth_reset_sent_at' => Time.zone.now.iso8601
          })

          context['reset_password_url'] = options.reset_password_url + '?auth_reset_token=' + entry['_auth_reset_token']
          context[options.type.singularize] = entry

          send_reset_password_instructions(options, context)

          :"reset_#{options.password_field}_instructions_sent"
        end
      end

      def reset_password(options, request)
        return :invalid_token       if options.reset_token.blank?
        return :password_too_short  if options.password.to_s.size < ContentEntry::MIN_PASSWORD_LENGTH
        return :invalid_password    unless ContentEntry.storable_password?(options.password)

        entry = entries.all(options.type, '_auth_reset_token' => options.reset_token).first

        if entry
          sent_at = Time.parse(entry[:_auth_reset_sent_at]).to_i
          now = Time.zone.now.to_i - RESET_TOKEN_LIFETIME

          if sent_at >= now
            entries.update_decorated_entry(entry, {
              "#{options.password_field}_hash" => BCrypt::Password.create(options.password),
              '_auth_reset_token'   => nil,
              '_auth_reset_sent_at' => nil
            })
            notify(:reset_password, entry, request)

            return [:"#{options.password_field}_reset", entry]
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

      def sign_up_password(options)
        options.entry.with_indifferent_access[options.password_field] if options.entry.is_a?(Hash)
      end

      def refused_sign_up(options, password)
        entry = entries.build(options.type, options.entry)
        return unless entry

        field = options.password_field.to_sym

        if ContentEntry.blank_password?(password) && password.to_s.size < ContentEntry::MIN_PASSWORD_LENGTH
          entry.errors.add(field, :too_short, count: ContentEntry::MIN_PASSWORD_LENGTH)
        else
          entry.errors.add(field, :invalid)
        end

        entry
      end

      def send_welcome_email(options, context)
        return if options.disable_email

        send_email options, context, <<-EMAIL
Hi,
You've been successfully registered.
Thanks!
EMAIL
      end

      def send_reset_password_instructions(options, context)
        send_email options, context, <<-EMAIL
Hi,
To reset your password please follow the link below: #{context['reset_password_url']}.
Thanks!
EMAIL
      end

      def send_email(options, context, default_body)
        email_options = { from: options.from, to: options.id, subject: options.subject, smtp: options.smtp }

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

          # Sign-up must target a declared password field.
          if !content_type.fields_by_name[password_field]&.write_only?
            errors.add(password_field, :invalid)
          elsif self[confirmation].nil?
            errors.add(confirmation, :confirmation, attribute: _label_of(password_field))
          end

          errors.empty?
        end

      end

    end

  end
end
