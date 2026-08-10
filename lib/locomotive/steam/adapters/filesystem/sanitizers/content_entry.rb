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
              _apply_to_dataset(entity, dataset)
            end
          end

          def apply_to_entity_with_dataset(entity, dataset)
            # Note: this statement attaches the site to the entity
            apply_to_entity(entity)

            _apply_to_dataset(entity, dataset)
          end

          private

          def _apply_to_dataset(entity, dataset)
            set_slug(entity, dataset)
            set_id(entity)
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

          def set_id(entity)
            # don't override the id if it was set from a MongoDB dump
            return if entity._id.to_s =~ /[a-z0-9]{12,}/

            if (slug = entity[:_slug]).respond_to?(:translations)
              entity[:_id] = slug[locale]
            else
              entity[:_id] = slug
            end
          end

          def set_slug(entity, dataset)
            return unless entity._slug.blank?

            entity[:_slug] ||= Locomotive::Steam::Models::I18nField.new(:_slug, nil)

            unless entity._label.respond_to?(:translations)
              # same value for any locale
              entity[:_slug].translations = slugify(entity._id, entity._label, dataset)
              return
            end

            # An entry is reachable by slug in every locale, even the ones its
            # label was never translated into.
            locales.each do |locale|
              label = entity._label[locale] || entity._label[default_locale]

              entity[:_slug][locale] = slugify(entity._id, label, dataset, locale)
            end
          end

          def slugify(id, label, dataset, locale = nil)
            base, index = label.to_s.permalink(false), nil
            _slugify = -> (i) { [base, i].compact.join('-') }

            while !is_slug_unique?(id, _slugify.call(index), dataset, locale)
              index = index ? index + 1 : 1
            end

            _slugify.call(index)
          end

          def is_slug_unique?(id, slug, dataset, locale)
            dataset.query(locale) { where(_slug: slug, k(:_id, :ne) => id) }.first.nil?
          end

        end

      end
    end
  end
end
