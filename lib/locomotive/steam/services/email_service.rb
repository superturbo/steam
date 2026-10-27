require 'pony'

module Locomotive
  module Steam

    class EmailService

      attr_accessor_initialize :page_finder_service, :liquid_parser, :asset_host, :simulation, [:log_rules]

      def send_email(options, context)
        prepare_options(options, context)

        log(options, simulation)

        !simulation ? send_email!(options) : nil
      end

      def send_email!(options)
        Pony.mail(options)
      end

      def logger
        Locomotive::Common::Logger
      end

      private

      def prepare_options(options, context)
        build_body(options.symbolize_keys!, context, options.delete(:html))

        extract_attachment(options)

        options[:via] ||= :smtp
        options[:via_options] ||= options.delete(:smtp).try(:symbolize_keys)

        if (enable_starttls_auto = options[:via_options][:enable_starttls_auto]).present?
          options[:via_options][:enable_starttls_auto] = Locomotive::Steam::TRUTHY_VALUES.include?(enable_starttls_auto)
        end
      end

      def build_body(options, context, html = true)
        key = html || html.nil? ? :html_body : :body

        document = (if handle = options.delete(:page_handle)
          parse_page(handle)
        elsif body = options.delete(:body)
          liquid_parser.parse_string(body)
        else
          raise "[EmailService] the body or page_handle options are missing."
        end)

        options[key] = document.render(context)
      end

      def parse_page(handle)
        if page = page_finder_service.by_handle(handle, false)
          liquid_parser.parse(page) # the liquid parser decorates the page (i18n)
        else
          raise "[EmailService] No page found with the following handle: #{handle}"
        end
      end

      def extract_attachment(options)
        (options[:attachments] || {}).each do |filename, value|
          options[:attachments][filename] = read_attachment(value)
        end
      end

      def read_attachment(value)
        url = case value
        when /^https?:\/\// then value
        when /^\//          then asset_host.compute(value, false)
        else
          nil
        end

        url ? _read_http_attachment(url) : value
      end

      def _read_http_attachment(url)
        begin
          uri = URI(url)
          Net::HTTP.get(uri)
        rescue Exception => e
          filtered = LogFilter.url(url, log_rules)
          logger.error "[SendEmail] Unable to read the attachment #{filtered}: #{e.class} #{e.message.gsub(url, filtered)}"
          nil
        end
      end

      def log(options, simulation)
        server = "via #{options[:via]} (#{options[:via_options]&.values_at(:address, :port)&.compact&.join(':')})"

        if simulation
          logger.info email_preview("[SendEmail] Email preview, not sent #{server}:", options)
        else
          logger.info "[SendEmail] Delivery requested #{server}"
          logger.debug email_preview('[SendEmail] Email:', options) if logger.instance.logger&.debug?
        end
      end

      def email_preview(heading, options)
        message = [heading]
        message << "From:     #{options[:from]}"
        message << "To:       #{options[:to]}"
        message << "Subject:  #{options[:subject]}"
        message << "Attachments:  #{(options[:attachments] || {}).keys.join(', ')}"
        message << "-----------"
        message << (options[:body] || options[:html_body]).gsub("\n", "\n\t")
        message << "-----------"

        message.join("\n") + "\n\n"
      end

    end

  end
end
