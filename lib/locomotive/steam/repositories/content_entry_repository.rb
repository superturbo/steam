require_relative '../adapters/numeric_bounds'

module Locomotive
  module Steam

    class ContentEntryRepository

      include Models::Repository

      class InvalidDefault < ArgumentError; end

      attr_accessor :content_type_repository, :content_type

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
      end

      # Entity mapping
      mapping :content_entries, entity: ContentEntry do
        localized_attributes :_slug, :seo_title, :meta_description, :meta_keywords

        default_attribute :content_type, -> (repository) { repository.content_type }
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

      def build(attributes, &block)
        super(with_field_defaults(attributes), &block)
      end

      def count(conditions = {})
        conditions, _ = conditions_without_order_by(conditions)
        super() { where(conditions) }
      end

      def find(id)
        conditions, _ = conditions_without_order_by(_id: self.adapter.make_id(id))
        first { where(conditions) }
      end

      def first(conditions = {}, &block)
        ordered_entries(conditions, &block).first
      end

      def last(&block)
        ordered_entries({}, &block).all.last
      end

      def exists?(conditions = {})
        conditions, _ = conditions_without_order_by(conditions)
        !query { where(conditions) }.empty?
      end

      def by_slug(slug)
        conditions, _ = conditions_without_order_by(_slug: slug)
        first { where(conditions) }
      end

      def value_for(entry, name, conditions = {})
        return nil if entry.nil?

        if field = content_type.fields_by_name[name]
          value = entry.send(name)

          if %i(has_many many_to_many).include?(field.type)
            # a safe copy of the proxy repository is needed here
            value = value.dup

            # like this, we do not modify the original local conditions
            value.local_conditions.merge!(conditions) if conditions
          end

          value
        end
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

      def ordered_entries(conditions = {}, &block)
        conditions, order_by = conditions_without_order_by(conditions)

        # priority:
        # 1/ order_by passed in the conditions parameter
        # 2/ the default order (_position) defined in the content type
        order_by = order_sequence_for(order_by || content_type.order_by)

        query {
          (block_given? ? instance_eval(&block) : where).
            where(conditions).
              order_by(order_by)
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

        return criteria if criteria.any? { |name, _| name.to_s == '_slug' }

        criteria + [[:_slug, :asc]]
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

      def conditions_without_order_by(conditions = {})
        _conditions = prepare_conditions(conditions)
        order_by = _conditions.delete(:order_by) || _conditions.delete('order_by')
        [_conditions, order_by]
      end

      def prepare_conditions(*conditions)
        _conditions = Conditions.new(conditions.first, self.content_type.fields, simple_clone).prepare

        super(_conditions).tap do |final_conditions|
          # skip the default visible condition (_visible: true) by just passing nil
          skip_visible = final_conditions.stringify_keys.fetch('_visible', true).nil?

          # clean it
          final_conditions.delete(:_visible) || final_conditions.delete('_visible')

          final_conditions[:_visible] = true unless skip_visible
        end
      end

      def simple_clone
        self.class.new(self.adapter, self.site, self.locale, self.content_type_repository)
      end

      def add_localized_fields_to_mapper(mapper)
        unless self.content_type.localized_names.blank?
          mapper.localized_attributes(*self.content_type.localized_names)
        end
      end

      def add_associations_to_mapper(mapper)
        self.content_type.association_fields.each do |field|
          mapper.association(field.type, field.name, self.class, field.association_options, &method(:prepare_repository_for_association))
        end
      end

      # This code is executed once when the association proxy object receives a call to any method
      def prepare_repository_for_association(repository, options)
        # load the target content type
        _content_type = content_type_repository.find(options[:target_id])

        # the target repository uses this content type for all the other inner calls
        repository.with(_content_type)

        # the content type repository is also need by the target repository
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

      # The next slug sharing the ordering key, then the first entry of the
      # group the sequence reaches after it. Null sorts below every value, so
      # an ascending key steps out of the null group and a descending one ends
      # in it. A content type orders by one field, so _slug ends the sequence.
      def navigation_queries(entry, sequence)
        name, key_direction = sequence.first
        slug_direction      = sequence.last.last
        by_slug             = [[:_slug, slug_direction]]
        slug_step           = k(:_slug, slug_direction == :asc ? 'gt' : 'lt')
        slug                = i18n_value_of(entry, :_slug)

        # A type ordered by the slug puts one entry in every group.
        return [[{ slug_step => slug }, by_slug]] if name == :_slug

        value   = i18n_value_of(entry, name)
        queries = [[{ name => value, slug_step => slug }, by_slug]]

        if value.nil?
          queries << [{ k(name, 'ne') => nil }, sequence] if key_direction == :asc
        elsif key_direction == :asc
          queries << [{ k(name, 'gt') => value }, sequence]
        else
          queries << [{ k(name, 'lt') => value }, sequence] << [{ name => nil }, by_slug]
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

        # Numeric strings accept decimal notation only.
        INTEGER_FORMAT = /\A[+-]?\d+\z/.freeze
        FLOAT_FORMAT   = /\A[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?\z/.freeze

        private_constant :INTEGER_FORMAT, :FLOAT_FORMAT

        def initialize(conditions = {}, fields, target_repository)
          @conditions = Adapters::Query::Criteria.normalize(conditions)
          @fields = fields
          @target_repository = target_repository
          @locale = target_repository.locale
        end

        def prepare
          # _id (primary key)
          _prepare([Locomotive::Steam::ContentTypeField.new(name: '_id')], id_backed: true) do |_, value|
            value_to_primary_key(value)
          end

          # select
          _prepare(@fields.selects, id_backed: true) do |field, value|
            # FIXME: [only in Wagon], if the user changes the locale, since all content is stored in memory,
            # we have to change the locale in the repository used to fetch the select options.
            field.select_options.locale = @locale

            value_to_option_id(field, value)
          end

          # date
          _prepare(@fields.dates_and_date_times) { |field, value| value_to_date(value, field.type) }

          # integer / float
          _prepare(@fields.numbers) { |field, value| value_to_number(value, field.type) }

          # belongs_to
          _prepare(@fields.belongs_to, id_backed: true) { |field, value| value_to_id(value, field.target_id) }
          
          # many_to_many
          _prepare(@fields.many_to_many, id_backed: true) { |field, value| values_to_ids(value, field.target_id) }

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

        def value_to_primary_key(value)
          case value
          when Array then value.map { |element| value_to_primary_key(element) }
          when Set   then value.map { |element| value_to_primary_key(element) }
          else
            id = @target_repository.adapter.make_id(value)

            id == false ? Locomotive::Steam::Adapters::Query::Values.unmatchable : id
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
          when Array, Set    then value.any? { |element| contains_range_or_pattern?(element) }
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
          when Set   then value.map { |element| value_to_option_id(field, element) }
          else field.select_options.by_name(value).try(:_id) ||
               Locomotive::Steam::Adapters::Query::Values.unmatchable
          end
        end

        def values_to_ids(value, target_id)
          [*value].map { |_value| value_to_id(_value, target_id) }
        end

        def value_to_id(value, target_id)
          return values_to_ids(value, target_id) if value.kind_of?(Array)

          _value = if value.is_a?(Hash)
            value['_id'] || value[:_id]
          else
            value.respond_to?(:_id) ? value._id : value
          end

          if (id = @target_repository.adapter.make_id(_value)) == false
            slug_to_id(value, target_id)
          else
            id
          end
        end

        def slug_to_id(slug, target_id)
          return nil if slug.blank?

          if _repository = @target_repository.with(target_id)
            _entry = _repository.first { where(_slug: slug).only(:_id) }
            _entry.try(:_id)
          end
        end

        def value_to_date(value, type)
          case value
          # a Range or Regexp is its own plain-field expression, not an operand
          when nil, Range, Regexp then value
          when Array then value.map { |element| value_to_date(element, type) }
          when Set   then value.map { |element| value_to_date(element, type) }
          else
            parsed    = value.is_a?(String) ? parse_date(value) : value
            converter = type == :date ? :to_date : :to_datetime

            unless parsed.respond_to?(converter)
              raise Locomotive::Steam::Adapters::Query::InvalidValue,
                    "expected a date-compatible value, got #{value.inspect}"
            end

            parsed.public_send(converter)
          end
        end

        # Numeric strings are coerced where field metadata is available.
        def value_to_number(value, type)
          case value
          # a Range or Regexp is its own plain-field expression, not an operand
          when nil, Range, Regexp then value
          when Numeric then validate_numeric_bounds!(value)
          when Array  then value.map { |element| value_to_number(element, type) }
          when Set    then value.map { |element| value_to_number(element, type) }
          when String then parse_number(value, type)
          else
            raise Locomotive::Steam::Adapters::Query::InvalidValue,
                  "expected a number, got #{value.inspect}"
          end
        end

        # Invalid numeric strings remain strings, avoiding errors and nil
        # semantics.
        def parse_number(value, type)
          candidate = value.strip
          format    = type == :integer ? INTEGER_FORMAT : FLOAT_FORMAT

          return value unless format.match?(candidate)

          number = type == :integer ? Integer(candidate, 10) : Float(candidate)

          within_numeric_bounds?(number) ? number : value
        end

        # Typed numeric operands must stay within the supported query domain.
        def validate_numeric_bounds!(value)
          return value if within_numeric_bounds?(value)

          raise Locomotive::Steam::Adapters::Query::InvalidValue,
                "numeric value is outside supported bounds: #{value.inspect}"
        end

        # Typed integers outside BSON int64 and non-finite floats are invalid
        # operands. Other Numerics, BigDecimal among them, are left alone.
        def within_numeric_bounds?(number)
          case number
          when Integer, Float then Adapters::NumericBounds.within?(number)
          else true
          end
        end

        def parse_date(value)
          parsed = begin
            Time.zone.parse(value)
          rescue ArgumentError
            nil
          end

          parsed || raise(
            Locomotive::Steam::Adapters::Query::InvalidValue,
            "invalid date: #{value.inspect}"
          )
        end

      end

    end

  end
end
