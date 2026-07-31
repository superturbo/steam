class NoCacheStore
  def fetch(name, options = nil, &block); yield; end
end

# Keeps filesystem mutations visible within one adapter without sharing state.
class InstanceCacheStore

  def initialize
    @store = {}
  end

  def fetch(name, options = nil)
    return read(name) unless block_given?

    @store.key?(name) ? @store[name] : write(name, yield)
  end

  def read(name, options = nil)
    @store[name]
  end

  def write(name, value, options = nil)
    @store[name] = value
  end

  def delete(name)
    @store.delete(name)
  end

  def clear
    @store.clear
  end

end
