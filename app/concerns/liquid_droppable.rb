# frozen_string_literal: true

# Include this mix-in to make a class droppable to Liquid, and adjust
# its behavior in Liquid by implementing its dedicated Drop class
# named with a "Drop" suffix.
module LiquidDroppable
  extend ActiveSupport::Concern

  class Drop < Liquid::Drop
    def initialize(object)
      @object = object
    end

    def to_s
      @object.to_s
    end

    def each
      self.class.json_keys.each { |name|
        yield [name, __send__(name)]
      }
    end

    def self.json_keys
      @json_keys ||=
        public_instance_methods -
        Liquid::Drop.public_instance_methods -
        %i[to_liquid as_json each to_s]
    end

    def as_json
      Hash[self.class.json_keys.map { |m| [m.to_s, __send__(m).as_json]}]
    end
  end

  included do
    const_set :Drop,
              if Kernel.const_defined?(drop_name = "#{name}Drop")
                Kernel.const_get(drop_name)
              else
                Kernel.const_set(drop_name, Class.new(Drop))
              end
  end

  def to_liquid
    self.class::Drop.new(self)
  end

  class MatchDataDrop < Drop
    delegate :pre_match, :post_match, :names, :size, to: :@object

    def to_s
      @object[0]
    end

    def liquid_method_missing(method)
      @object[method]
    rescue IndexError
      nil
    end
  end

  class ::MatchData
    def to_liquid
      MatchDataDrop.new(self)
    end
  end

  require 'uri'

  class URIDrop < Drop
    delegate *URI::Generic::COMPONENT, to: :@object
  end

  class ::URI::Generic
    def to_liquid
      URIDrop.new(self)
    end
  end

  # This drop currently does not support the `slice` filter.
  class ActiveRecordCollectionDrop < Drop
    # compatibility with array
    delegate :each, :first, :last, to: :@object
    # as_json is provided by Enumerable
    include Enumerable

    delegate :count, to: :@object
    # compatibility with array; also required by the `size` filter
    alias size count

    # required for variable indexing as array
    delegate :fetch, to: :@object

    # required for variable indexing as array
    def [](i)
      case i
      when Integer
        @object[i]
      when 'size', 'count', 'first', 'last'
        # `{{ var.size }}` generates a call to `var['size']` because
        # we have `[]` defined.  The methods are still required
        # because filters check their existence with `respond_to?` and
        # directly call them.
        __send__(i)
      end
    end
  end

  class ::ActiveRecord::Associations::CollectionProxy
    def to_liquid
      ActiveRecordCollectionDrop.new(self)
    end
  end
end
