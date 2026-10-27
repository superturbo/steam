module Locomotive::Steam
  module Adapters
    module Filesystem
      module Sanitizers

        class ContentEntry

          include Adapters::Filesystem::Sanitizer

          def apply_to_entity(entity)
            super
            add_label(entity)
          end

          def apply_to_dataset(dataset)
            dataset.records.values.each do |entity|
              _apply_to_dataset(entity, dataset, default_locale)
            end
          end

          def apply_to_entity_with_dataset(entity, dataset)
            # Note: this statement attaches the site to the entity
            apply_to_entity(entity)

            _apply_to_dataset(entity, dataset, locale)
          end

          # Preserve array ids from MongoDB dumps and 24-character ObjectId strings.
          def self.pulled_id?(id)
            id.is_a?(Array) || (id.is_a?(String) && id.match?(/\A\h{24}\z/))
          end

          private

          # A loaded entry takes its id from the default locale, whichever locale
          # loads it. A created entry takes it from the locale it is created in.
          def _apply_to_dataset(entity, dataset, id_locale)
            set_slug(entity, dataset)
            set_id(entity, id_locale)
          end

          # YAML stores the label as the entry key, not as a field.
          def add_label(entity)
            value = entity.attributes.delete(:_label)
            name  = entity.content_type.label_field_name

            if entity.localized_attributes.key?(name)
              field = (entity.attributes[name] ||= Locomotive::Steam::Models::I18nField.new(name, nil))
              field[default_locale] = value
            else
              entity.attributes[name] ||= value
            end
          end

          def set_id(entity, id_locale)
            return if self.class.pulled_id?(entity._id)

            if (slug = entity[:_slug]).respond_to?(:translations)
              entity[:_id] = slug[id_locale]
            else
              entity[:_id] = slug
            end
          end

          def set_slug(entity, dataset)
            slug = entity[:_slug]

            if slug.respond_to?(:scalar_fallback?) && slug.scalar_fallback? && slug.default.present?
              slug.translations = every_locale(slug.default)
              return
            end

            return unless entity._slug.blank?

            entity[:_slug] ||= Locomotive::Steam::Models::I18nField.new(:_slug, nil)

            unless entity._label.respond_to?(:translations)
              generated = slugify(entity._id, entity._label, dataset, locales.presence || [nil])
              entity[:_slug].translations = every_locale(generated)
              return
            end

            # An entry is reachable by slug in every locale, even the ones its
            # label was never translated into.
            locales.each do |locale|
              label = entity._label[locale] || entity._label[default_locale]

              entity[:_slug][locale] = slugify(entity._id, label, dataset, [locale])
            end
          end

          # A slug shared by every locale has to be free in each of them.
          def slugify(id, label, dataset, locales)
            base, index = label.to_s.permalink(false), nil
            _slugify = -> (i) { [base, i].compact.join('-') }

            until locales.all? { |locale| is_slug_unique?(id, _slugify.call(index), dataset, locale) }
              index = index ? index + 1 : 1
            end

            _slugify.call(index)
          end

          def every_locale(value)
            locales.blank? ? value : locales.to_h { |locale| [locale, value] }
          end

          def is_slug_unique?(id, slug, dataset, locale)
            dataset.query(locale) { where(_slug: slug, k(:_id, :ne) => id) }.first.nil?
          end

        end

      end
    end
  end
end
