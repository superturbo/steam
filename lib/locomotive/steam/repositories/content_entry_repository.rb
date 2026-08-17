require_relative '../adapters/numeric_bounds'
require_relative '../adapters/time_precision'
require_relative '../content_field_values'

module Locomotive
  module Steam

    class ContentEntryRepository

      include Models::Repository

      class InvalidDefault < ArgumentError; end

      attr_accessor :content_type_repository, :content_type

      # Association enumeration falls back to the owner's ID sequence.
      attr_writer :id_order

      def initialize(adapter, site = nil, locale = nil, content_type_repository = nil)
        @adapter  = adapter
        @scope    = Locomotive::Steam::Models::Scope.new(site, locale)
        @content_type_repository = content_type_repository
        @local_conditions = {}
        @memoized_mappers = {}
      end

      def initialize_copy(source)
        super
        @memoized_mappers = {}
        @association_conditions = source.association_conditions.dup
      end

      # Entity mapping
      mapping :content_entries, entity: ContentEntry do
        localized_attributes :_slug, :seo_title, :meta_description, :meta_keywords

        default_attribute :content_type, -> (repository) { repository.content_type }
        default_attribute :site,         -> (repository) { repository.site }

        after_load { |entity, _| Locomotive::Steam::ContentFieldValues.deserialize_entry(entity) }
      end

      # this is the starting point of all the next methods.
      # type can be either an instance of the ContentTypeRepository class
      # or the id of a content type.
      def with(type)
        type = self.content_type_repository.find(type) if type.is_a?(String)

        self.content_type = type # used for creating the scope
        self.scope.context[:content_type] = type

        @local_conditions[:content_type_id] = type.try(:_id)

        self # chainable
      end

      def all(conditions = {}, &block)
        ordered_entries(conditions, &block).all
      end

      # New entries get defaults here; loads only reflect stored values.
      def build(attributes, &block)
        super(with_field_defaults(resolve_selects(attributes)), &block).tap do |entity|
          entity[:_visible]  = true unless entity.attributes.key?(:_visible)
          entity[:_position] = 0    unless entity.attributes.key?(:_position)
        end
      end

      # A select named by its field takes an option name or an option;
      # its persisted key is the explicit id. Naming both is ambiguous and
      # fails validation, like an unknown name.
      def resolve_selects(attributes)
        content_type.fields.selects.each_with_object(attributes.dup) do |field, memo|
          name_keys = memo.keys.select { |key| key.to_s == field.name.to_s }
          id_keys   = memo.keys.select { |key| key.to_s == field.persisted_name.to_s }

          next if name_keys.empty? && id_keys.size <= 1

          values = name_keys.map { |key| memo.delete(key) }

          memo[field.persisted_name.to_sym] =
            if name_keys.size > 1 || id_keys.size > 1 || (name_keys.any? && id_keys.any?)
              id_keys.each { |key| memo.delete(key) }
              ContentEntry::INVALID_SELECT_VALUE
            else
              select_value_to_id(field, values.first)
            end
        end
      end

      def count(conditions = {})
        clauses, _ = query_parts(conditions)
        super() { clauses.each { |clause| where(clause) } }
      end

      def count_up_to(maximum, conditions = {})
        clauses, _ = query_parts(conditions)
        super(maximum) { clauses.each { |clause| where(clause) } }
      end

      def find(id)
        clauses, _ = query_parts(_id: self.adapter.make_id(id))
        first { clauses.each { |clause| where(clause) } }
      end

      def first(conditions = {}, &block)
        ordered_entries(conditions, &block).first
      end

      def last(&block)
        ordered_entries({}, &block).all.last
      end

      def exists?(conditions = {})
        clauses, _ = query_parts(conditions)
        !query { clauses.each { |clause| where(clause) } }.empty?
      end

      def by_slug(slug)
        clauses, _ = query_parts(_slug: slug)
        first { clauses.each { |clause| where(clause) } }
      end

      def association_conditions
        @association_conditions ||= {}
      end

      attr_writer :association_conditions

      protected :association_conditions, :association_conditions=

      def value_for(entry, name, conditions = {})
        return nil if entry.nil?

        if field = content_type.fields_by_name[name]
          value = entry.send(name)

          if %i(has_many many_to_many).include?(field.type) && conditions.present?
            value = value.with_conditions(conditions)
          end

          value
        end
      end

      def create(entity)
        raise InvalidEntry.new(entity) unless entity.valid?

        # One instant fills the moments the caller left out; a spelled-out
        # moment normalizes the same way, and an explicit null stays a null.
        now = Adapters::TimePrecision.utc_ms
        %i(created_at updated_at).each do |name|
          if entity.attributes.key?(name)
            entity[name] = Adapters::TimePrecision.utc_ms(entity[name]) unless entity[name].nil?
          else
            entity[name] = now
          end
        end

        super
      end

      def update(entity)
        raise InvalidEntry.new(entity) unless entity.valid?

        # Steam owns updated_at; whatever the caller put there loses.
        entity[:updated_at] = Adapters::TimePrecision.utc_ms

        super
      end

      def inc(entity, attribute, amount = 1)
        super(entity, attribute, increment_amount(attribute, amount))
      end

      def next(entry)
        navigate(entry, :next)
      end

      def previous(entry)
        navigate(entry, :previous)
      end

      def group_by_select_option(name)
        return {} if name.nil? || content_type.nil? || content_type.fields_by_name[name].type != :select

        # a big one request to get them grouped by the field
        _groups = all.group_by { |entry| i18n_value_of(entry, name) }

        groups_to_array(name, _groups).tap do |groups|
          # entries with a non existing select_option value?
          unless _groups.blank?
            groups << { name: nil, entries: _groups.values.flatten }.with_indifferent_access
          end
        end
      end

      def to_liquid
        Locomotive::Steam::Liquid::Drops::ContentEntryCollection.new(content_type, self)
      end

      private

      # Only field types with the same ordering in both adapters are allowed.
      ORDERABLE_FIELD_TYPES = %i(string text integer float boolean date date_time).freeze

      ORDERABLE_SYSTEM_FIELDS = %w(_slug _position _visible created_at updated_at).freeze

      INCREMENTABLE_FIELD_TYPES = %i(integer float).freeze

      private_constant :ORDERABLE_FIELD_TYPES, :ORDERABLE_SYSTEM_FIELDS, :INCREMENTABLE_FIELD_TYPES

      # A default fills a field the attributes leave out. An explicit null is a
      # value, and a stored entry is never revisited, so the two stay apart.
      def with_field_defaults(attributes)
        content_type.fields_with_default.each_with_object(attributes.dup) do |field, memo|
          name = field.persisted_name.to_s

          next if memo.key?(name) || memo.key?(name.to_sym)

          # Defaults must not be shared between entries.
          memo[name] = default_value_for(field).deep_dup
        end
      end

      # A select default names an option, while an entry stores the option id.
      def default_value_for(field)
        value = field.type == :select ? select_default_id(field) : field.default

        # Materialize scalar localized defaults for persistence.
        return value unless field.localized? && !value.is_a?(Hash)

        site.locales.to_h { |locale| [locale.to_s, value] }
      end

      def select_default_id(field)
        option = content_type_repository.select_options(content_type, field.name)
                   .detect { |candidate| candidate.name[site.default_locale] == field.default }

        unless option
          raise InvalidDefault,
                "#{content_type.slug}.#{field.name} has no option named #{field.default.inspect}"
        end

        option._id
      end

      # A scalar name resolves in the active locale, falling back to the
      # site default; a hash names its locales itself, so it only fits a
      # localized select.
      def select_value_to_id(field, value, locale = self.locale || site.try(:default_locale))
        case value
        when nil then nil
        when Hash
          return ContentEntry::INVALID_SELECT_VALUE unless field.localized?

          value.to_h { |_locale, name| [_locale, select_value_to_id(field, name, _locale)] }
        when String, Symbol then option_id_by_name(field, value.to_s, locale)
        else value.respond_to?(:_id) ? value._id : ContentEntry::INVALID_SELECT_VALUE
        end
      end

      def option_id_by_name(field, name, locale)
        option = field.select_options.scope.with_locale(locale) do
          field.select_options.by_name(name)
        end

        option ? option._id : ContentEntry::INVALID_SELECT_VALUE
      end

      def increment_amount(attribute, amount)
        field = content_type.fields_by_name[attribute.to_s]

        unless field && INCREMENTABLE_FIELD_TYPES.include?(field.type)
          raise InvalidIncrement, "#{content_type.slug}.#{attribute} is not a number"
        end

        # A float field keeps its type whatever whole number it is given.
        integer = field.type == :integer
        amount  = amount.to_f if !integer && amount.is_a?(Integer)

        unless amount.instance_of?(integer ? Integer : Float) && Adapters::NumericBounds.within?(amount)
          raise InvalidIncrement, "#{content_type.slug}.#{attribute} cannot take #{amount.inspect}"
        end

        amount
      end

      attr_reader :id_order

      def ordered_entries(conditions = {}, &block)
        clauses, order_by = query_parts(conditions)

        # priority:
        # 1/ order_by passed in the conditions parameter
        # 2/ the order the association or the content type declares
        # 3/ the owner's ID sequence
        if order_by.nil? && id_order
          ids = id_order

          return query {
            instance_eval(&block) if block_given?
            clauses.each { |clause| where(clause) }
            in_id_order(ids)
          }
        end

        sequence = order_sequence_for(order_by || content_type.order_by)

        query {
          instance_eval(&block) if block_given?
          clauses.each { |clause| where(clause) }
          order_by(sequence)
        }
      end

      # Equal sort values have no defined order in either adapter.
      def order_sequence_for(spec)
        criteria = Adapters::Query::OrderBy.decode(spec)

        criteria.each do |name, _|
          field = content_type.fields_by_name[name.to_s]

          next if orderable?(field, name.to_s)

          raise Adapters::Query::InvalidValue,
                "#{name} cannot order entries of #{content_type.slug}"
        end

        # _position and the current locale's _slug are already total.
        return criteria if criteria.any? { |name, _| name == :_position || name == :_slug }

        # Match the primary direction so one compound index serves both directions.
        criteria + [[:_position, criteria.first&.last || :asc]]
      end

      def orderable?(field, name)
        return ORDERABLE_FIELD_TYPES.include?(field.type) if field

        ORDERABLE_SYSTEM_FIELDS.include?(name) || inverse_position?(name)
      end

      # Inverse positions are named after their belongs_to field.
      def inverse_position?(name)
        prefix = 'position_in_'
        return false unless name.start_with?(prefix)

        content_type.fields_by_name[name.delete_prefix(prefix)]&.type == :belongs_to
      end

      def mapper
        key = self.content_type._id.to_s

        return @memoized_mappers[key] if @memoized_mappers[key]

        @memoized_mappers[key] = super(false).tap do |mapper|
          add_localized_fields_to_mapper(mapper)
          add_associations_to_mapper(mapper)
        end
      end

      def query_parts(conditions = {})
        sources = normalized_condition_sources(conditions)
        local   = local_conditions.with_indifferent_access

        caller_order = sources.filter_map { |source| source.delete(:order_by) }.first
        local_order  = local.delete(:order_by)

        order_by = caller_order || local_order

        clauses = sources.reject(&:blank?)
        clauses << local if local.present?

        [apply_visibility(clauses), order_by]
      end

      def normalized_condition_sources(conditions)
        [conditions, association_conditions].reject(&:blank?).map do |source|
          HashWithIndifferentAccess.new(Conditions.new(source, self.content_type.fields, simple_clone).prepare)
        end
      end

      def apply_visibility(clauses)
        visibilities = []
        clauses.each do |clause|
          visibilities << clause.delete(:_visible) if clause.key?(:_visible)
        end

        # nil disables only the default visibility filter.
        visibilities << true if visibilities.empty?

        visibilities.each do |visibility|
          case visibility
          when true, false then clauses << HashWithIndifferentAccess.new(_visible: visibility)
          when nil
          else
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  '_visible takes a boolean or nil'
          end
        end

        clauses.reject(&:blank?)
      end

      def simple_clone
        self.class.new(self.adapter, self.site, self.locale, self.content_type_repository)
      end

      def add_localized_fields_to_mapper(mapper)
        unless self.content_type.localized_names.blank?
          mapper.localized_attributes(*self.content_type.localized_names)
        end

        mapper.virtual_attributes(*self.content_type.select_fields.map(&:name))
      end

      def add_associations_to_mapper(mapper)
        self.content_type.association_fields.each do |field|
          mapper.association(field.type, field.name, self.class, field.association_options, &method(:prepare_repository_for_association))
        end
      end

      # Runs once per proxy, when its load path first needs the repository.
      def prepare_repository_for_association(repository, options)
        content_type = content_type_repository.find(options[:target_id])

        repository.with(content_type)
        repository.content_type_repository = content_type_repository
      end

      def navigate(entry, direction)
        return nil if entry.nil?

        with(entry.content_type)

        navigation_queries(entry, navigation_sequence(direction)).each do |conditions, order_by|
          neighbour = first(conditions.merge(order_by: order_by))

          return neighbour if neighbour
        end

        nil
      end

      # Navigation follows the default sequence, read backwards for previous.
      def navigation_sequence(direction)
        sequence = order_sequence_for(content_type.order_by)

        return sequence if direction == :next

        sequence.map { |field, order| [field, order == :asc ? :desc : :asc] }
      end

      # Try the next total key in this group, then the next primary group.
      # Null sorts below non-null values.
      def navigation_queries(entry, sequence)
        step_name, step_direction = sequence.last
        step_order = [[step_name, step_direction]]
        step_key   = k(step_name, step_direction == :asc ? 'gt' : 'lt')
        step_value = step_name == :_slug ? i18n_value_of(entry, :_slug) : entry[step_name]

        # A total primary needs no group fallback.
        return [[{ step_key => step_value }, step_order]] if sequence.size == 1

        name, key_direction = sequence.first
        value   = i18n_value_of(entry, name)
        queries = [[{ name => value, step_key => step_value }, step_order]]

        if value.nil?
          queries << [{ k(name, 'ne') => nil }, sequence] if key_direction == :asc
        elsif key_direction == :asc
          queries << [{ k(name, 'gt') => value }, sequence]
        else
          queries << [{ k(name, 'lt') => value }, sequence] << [{ name => nil }, step_order]
        end

        queries
      end

      def groups_to_array(name, groups)
        content_type_repository.select_options(content_type, name).map do |option|
          option_name = i18n_value_of(option, :name)
          { 'name' => option_name, 'entries' => groups.delete(option_name) || [] }.with_indifferent_access
        end
      end

      class Conditions

        def initialize(conditions = {}, fields, target_repository)
          @conditions = Adapters::Query::Criteria.normalize(conditions)
          @fields = fields
          @target_repository = target_repository
          @locale = target_repository.locale
        end

        def prepare
          # _id (primary key)
          _prepare([Locomotive::Steam::ContentTypeField.new(name: '_id', type: 'id')], id_backed: true) do |field, value|
            value_to_primary_key(value, field)
          end

          # select
          _prepare(@fields.selects, id_backed: true) do |field, value|
            # FIXME: [only in Wagon], if the user changes the locale, since all content is stored in memory,
            # we have to change the locale in the repository used to fetch the select options.
            field.select_options.locale = @locale

            value_to_option_id(field, value)
          end

          # date
          _prepare(@fields.dates_and_date_times) { |field, value| value_to_date(value, field) }

          # integer / float
          _prepare(@fields.numbers) { |field, value| value_to_number(value, field) }

          # boolean
          _prepare(@fields.booleans) { |field, value| value_to_boolean(value, field) }

          # belongs_to
          _prepare(@fields.belongs_to, id_backed: true) { |field, value| value_to_id(value, field) }

          # many_to_many
          _prepare(@fields.many_to_many, id_backed: true) { |field, value| values_to_ids(value, field) }

          @conditions
        end

        protected

        # exists takes a boolean and size an element count, so neither operand is
        # a field value the repository should convert — the registry owns them.
        NON_FIELD_VALUE_KINDS = %i(boolean size).freeze

        private_constant :NON_FIELD_VALUE_KINDS

        # Prepare every criterion independently; a field may have multiple bounds.
        def _prepare(fields, id_backed: false, &block)
          by_name = fields.index_by { |field| field.name.to_s }

          return if by_name.empty?

          @conditions.keys.each do |key|
            name, operator = Adapters::Query::Operators.decode(key)
            field = by_name[name]

            next if field.nil?

            value       = @conditions.delete(key)
            field_value = operator.nil? || !NON_FIELD_VALUE_KINDS.include?(operator.value_kind)

            validate_id_query!(name, operator, value) if id_backed && field_value

            new_name = field.persisted_name + (operator ? ".#{operator.name}" : '')

            @conditions[new_name] =
              if operator && NON_FIELD_VALUE_KINDS.include?(operator.value_kind)
                value
              else
                yield(field, value)
              end
          end
        end

        def value_to_primary_key(value, field)
          case value
          when Array then value.map { |element| value_to_primary_key(element, field) }
          else
            id = @target_repository.adapter.make_id(value)

            id == false ? unmatchable(field, :invalid_id) : id
          end
        end

        ORDERING_OPERATORS = %i(gt gte lt lte).freeze

        private_constant :ORDERING_OPERATORS

        # A field matched by id has no order the stores agree on: a Filesystem
        # _id is a slug and a select option is its position, where MongoDB
        # issues an ObjectId.
        def validate_id_query!(name, operator, value)
          if operator && ORDERING_OPERATORS.include?(operator.name)
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "#{name} is matched by id, which has no order: #{operator.name}"
          end

          return unless contains_range_or_pattern?(value)

          raise Locomotive::Steam::Adapters::Query::InvalidValue,
                "#{name} is matched by id, which a range or pattern cannot describe"
        end

        def contains_range_or_pattern?(value)
          case value
          when Range, Regexp then true
          when Array then value.any? { |element| contains_range_or_pattern?(element) }
          when Hash          then value.values.any? { |element| contains_range_or_pattern?(element) }
          else false
          end
        end

        # An unresolved name must not gain nil semantics, and false is a value
        # a field can hold.
        def value_to_option_id(field, value)
          case value
          when nil   then nil
          when Array then value.map { |element| value_to_option_id(field, element) }
          else field.select_options.by_name(value).try(:_id) ||
               unmatchable(field, :unknown_select_option)
          end
        end

        # A lone nil keeps nil semantics; only a real list maps element-wise.
        def values_to_ids(value, field)
          return nil if value.nil?

          [*value].map { |_value| value_to_id(_value, field) }
        end

        # Strings are slugs; IDs must be explicit. Inferring from string shape
        # gives the same operand different meanings across adapters.
        def value_to_id(value, field)
          case value
          when nil            then nil
          when Array          then values_to_ids(value, field)
          when String, Symbol then slug_to_id(value.to_s, field)
          when Hash           then explicit_id(value['_id'] || value[:_id], field)
          else value.respond_to?(:_id) ? explicit_id(value._id, field) : explicit_id(value, field)
          end
        end

        # Only a direct nil operand has missing-association semantics.
        def explicit_id(id, field)
          return unmatchable(field, :invalid_id) if id.nil?

          key = @target_repository.adapter.make_id(id)

          key == false ? unmatchable(field, :invalid_id) : key
        end

        # An unresolved slug must not gain nil semantics; only a real nil keeps it.
        def slug_to_id(slug, field)
          return nil if slug.nil?

          _entry = @target_repository.with(field.target_id).first { where(_slug: slug).only(:_id) }

          _entry.try(:_id) || unmatchable(field, :unknown_slug)
        end

        def value_to_date(value, field)
          case value
          # a Regexp is its own plain-field expression, not an operand
          when nil, Regexp then value
          when Range  then date_range(value, field)
          when Array  then value.map { |element| value_to_date(element, field) }
          when String then parse_date(value, field)
          else typed_date_operand(value, field.type)
          end
        end

        def value_to_boolean(value, field)
          case value
          # a Range or Regexp is its own plain-field expression, not an operand
          when nil, Range, Regexp then value
          when Array       then value.map { |element| value_to_boolean(element, field) }
          when true, false then value
          when String      then parse_boolean(value, field)
          else
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "expected a boolean, got #{value.inspect}"
          end
        end

        # Numeric strings are coerced where field metadata is available.
        def value_to_number(value, field)
          case value
          # a Regexp is its own plain-field expression, not an operand
          when nil, Regexp then value
          when Range   then numeric_range(value, field)
          when Numeric then validate_numeric_bounds!(value)
          when Array  then value.map { |element| value_to_number(element, field) }
          when String then parse_number(value, field)
          else
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "expected a number, got #{value.inspect}"
          end
        end

        # Bounds meet the same rules as comparison operands: text is read
        # as a date or matches nothing, a wrong type raises.
        def date_range(range, field)
          low  = date_range_bound(range.begin, field)
          high = date_range_bound(range.end, field)

          if [low, high].any? { |bound| Locomotive::Steam::Adapters::Query::Values.unmatchable?(bound) }
            return Locomotive::Steam::Adapters::Query::Values.unmatchable
          end

          Range.new(low, high, range.exclude_end?)
        end

        def date_range_bound(value, field)
          case value
          when nil then nil
          when Array, Hash, Range, Regexp
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "#{value.class} cannot bound a date range"
          else value_to_date(value, field)
          end
        end

        # Bounds meet the same rules as comparison operands: text is read
        # as a number or matches nothing, a wrong type raises.
        def numeric_range(range, field)
          low  = numeric_range_bound(range.begin, field)
          high = numeric_range_bound(range.end, field)

          if [low, high].any? { |bound| Locomotive::Steam::Adapters::Query::Values.unmatchable?(bound) }
            return Locomotive::Steam::Adapters::Query::Values.unmatchable
          end

          Range.new(low, high, range.exclude_end?)
        end

        def numeric_range_bound(value, field)
          case value
          when nil then nil
          when Array, Hash, Range, Regexp
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "#{value.class} cannot bound a numeric range"
          else value_to_number(value, field)
          end
        end

        # Invalid strings cannot equal a valid field value.
        def parse_number(value, field)
          Locomotive::Steam::ContentFieldValues.number(value, field.type)
        rescue Locomotive::Steam::ContentFieldValues::ParseError => error
          unmatchable(field, error.reason)
        end

        def typed_date_operand(value, type)
          ContentFieldValues.normalize_input(type, value, @target_repository.site)
        rescue Locomotive::Steam::ContentFieldValues::ParseError => error
          raise Locomotive::Steam::Adapters::Query::InvalidValue, error.message
        end

        def parse_boolean(value, field)
          Locomotive::Steam::ContentFieldValues.boolean(value)
        rescue Locomotive::Steam::ContentFieldValues::ParseError => error
          unmatchable(field, error.reason)
        end

        def validate_numeric_bounds!(value)
          return value if Adapters::NumericBounds.within?(value)

          raise Locomotive::Steam::Adapters::Query::InvalidValue,
                "#{value.class} is not a supported numeric operand or is outside its bounds"
        end

        def parse_date(value, field)
          ContentFieldValues.coerce_date_operand(value, field.type, @target_repository.site)
        rescue Locomotive::Steam::ContentFieldValues::ParseError => error
          unmatchable(field, error.reason)
        end

        # Production stays silent; Wagon reports only field context and reason.
        def unmatchable(field, reason)
          if Locomotive::Steam.configuration.mode == :test && (@reported_rejections ||= Set.new).add?([field.name, field.type, reason])
            Locomotive::Common::Logger.warn "[Steam query] operand for #{field.name.inspect} " \
                                            "(type: #{field.type}) was rejected (#{reason}) and matches nothing"
          end

          Locomotive::Steam::Adapters::Query::Values.unmatchable
        end

      end

    end

  end
end
