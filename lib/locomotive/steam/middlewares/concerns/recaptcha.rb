module Locomotive::Steam
  module Middlewares
    module Concerns
      module Recaptcha

        def is_recaptcha_valid?(slug, response_code)
          return true unless is_recaptcha_required?(slug)

          details = services.recaptcha.verify(response_code)
          status = recaptcha_status(details, site_metafields, slug)

          liquid_assigns['recaptcha_invalid'] = !status[:overall]
          log_recaptcha(status)

          status[:overall]
        end

        def is_recaptcha_required?(slug)
          services.content_entry.get_type(slug)&.recaptcha_required?
        end

        def build_invalid_recaptcha_entry(slug, entry_attributes)
          services.content_entry.build(slug, entry_attributes).tap do |entry|
            entry.errors.add(:recaptcha_invalid, true)
          end
        end

        private

        def recaptcha_status(details, metafields, slug)
          expected_hostnames = site.domains
          expected_threshold = recaptcha_score_threshold(metafields)
          expected_action = slug.to_s

          actual_hostname = details['hostname']
          actual_action = details['action']
          actual_score = details['score']

          success = details['success'] == true
          hostname_valid = expected_hostnames.include?(actual_hostname)
          action_valid = actual_action == expected_action
          score_valid = recaptcha_score_valid?(actual_score, expected_threshold)
          has_errors = details['error-codes'].present?

          overall = success && hostname_valid && action_valid && (score_valid.nil? || score_valid) && !has_errors

          {
            overall: overall,
            success: success,
            hostname_valid: hostname_valid,
            action_valid: action_valid,
            score_valid: score_valid,
            has_errors: has_errors,
            actual_hostname: actual_hostname,
            actual_action: actual_action,
            actual_score: actual_score,
            error_codes: details['error-codes'],
            expected_hostnames: expected_hostnames,
            expected_action: expected_action,
            expected_threshold: expected_threshold
          }
        end

        def recaptcha_score_valid?(score, threshold)
          return nil unless threshold && (0.0..1.0).cover?(threshold)

          score >= threshold
        end

        def recaptcha_score_threshold(metafields)
          Float(metafields[:recaptcha_score_threshold]) rescue nil
        end

        def site_metafields
          site.metafields.values.reduce({}, :merge).with_indifferent_access
        end

        def log_recaptcha(status)
          recaptcha = "[Recaptcha]".colorize(status[:overall] ? :green : :red)
          success = "success=#{status[:success]}".colorize(status[:success] ? :green : :red)

          if status[:hostname_valid]
            hostname = "hostname=#{status[:actual_hostname]}".colorize(:green)
          else
            hostname = "hostname=#{status[:actual_hostname]} expected_hostnames=#{status[:expected_hostnames].inspect}".colorize(:red)
          end

          if status[:action_valid]
            action = "action=#{status[:actual_action]}".colorize(:green)
          else
             action = "action=#{status[:actual_action]} expected_action=#{status[:expected_action]}".colorize(:red)
          end

          if status[:score_valid].nil?
            score = "score=#{status[:actual_score]}"
          elsif status[:score_valid]
            score = "score=#{status[:actual_score]}".colorize(:green)
          else
            score = "score=#{status[:actual_score]} expected_score_threshold=#{status[:expected_threshold]}".colorize(:red)
          end

          errors = status[:has_errors] ? "errors_codes=#{status[:error_codes].inspect}".colorize(:red) : nil

          msg = "#{recaptcha} #{success} #{hostname} #{action} #{score} #{errors}"

          log msg
        end
      end
    end
  end
end
