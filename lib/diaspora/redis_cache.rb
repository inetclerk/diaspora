#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.
#

class RedisCache

  SUPPORTED_CACHES = [:created_at] #['updated_at', 
  CACHE_LIMIT = 100

  def initialize(user, order_field)
    @user = user
    @order_field = order_field.to_s
  end

  # Checks to see if the necessary redis cache variables are set in application.yml
  #
  # @return [Boolean]
  def self.configured?
    AppConfig[:redis_cache].present?
  end

  # @return [Boolean]
  def cache_exists?
    self.size != 0
  end

  # @return [Integer] the cardinality of the redis set
  def size
    redis.zcard(set_key)
  end

  def post_ids(time=Time.now, limit=15)
    post_ids = redis.zrevrangebyscore(set_key, time.to_i, "-inf")
    post_ids[0...limit]
  end

  def ensure_populated!
    self.repopulate! unless cache_exists?
  end

  def repopulate!
    self.populate! && self.trim!
  end

  def populate!
    # user executes query and gets back hashes
    sql = @user.visible_posts_sql(:type => RedisCache.acceptable_types, :limit => CACHE_LIMIT, :order => self.order)
    hashes = Post.connection.select_all(sql)

    # hashes are inserted into set in a single transaction
    redis.multi do
      hashes.each do |h|
        self.redis.zadd(set_key, h[@order_field].to_i, h["id"])
      end
    end
  end

  def trim!
    self.redis.zremrangebyrank(set_key, 0, -(CACHE_LIMIT+1))
  end

  # @param order [Symbol, String]
  # @return [Boolean]
  def self.supported_order?(order)
    SUPPORTED_CACHES.include?(order.to_sym)
  end

  def order
    "#{@order_field} DESC"
  end

  def add(score, id)
    return unless self.cache_exists?
    self.redis.zadd(set_key, score.to_i, id)
    self.trim!
  end

  # exposing the need to tie cache to a stream
  # @return [Array<String>] Acceptable Post types for the given cache
  def self.acceptable_types
    AspectStream::TYPES_OF_POST_IN_STREAM
  end

  protected
  # @return [Redis]
  def redis
    @redis ||= Redis.new(:host => RedisCache.redis_host, :port => RedisCache.redis_port)
  end

  def self.redis_host
    (AppConfig[:redis_location].blank?) ? nil : AppConfig[:redis_location]
  end

  def self.redis_port
    (AppConfig[:redis_port].blank?) ? nil : AppConfig[:redis_port]
  end

  # @return [String]
  def set_key
    @set_key ||= "cache_stream_#{@user.id}_#{@order_field}"
  end
end
