require 'oauth/helper'
require 'oauth/request_proxy/net_http'

class Net::HTTPGenericRequest
  include OAuth::Helper

  attr_reader :oauth_helper

  # Add the OAuth information to an HTTP request. Depending on the <tt>options[:scheme]</tt> setting
  # this may add a header, additional query string parameters, or additional POST body parameters.
  # The default scheme is +header+, in which the OAuth parameters as put into the +Authorization+
  # header.
  #
  # * http - Configured Net::HTTP instance
  # * consumer - OAuth::Consumer instance
  # * token - OAuth::Token instance
  # * options - Request-specific options (e.g. +request_uri+, +consumer+, +token+, +scheme+,
  #   +signature_method+, +nonce+, +timestamp+)
  #
  # This method also modifies the <tt>User-Agent</tt> header to add the OAuth gem version.
  #
  # See Also: {OAuth core spec version 1.0, section 5.4.1}[http://oauth.net/core/1.0#rfc.section.5.4.1],
  #           {OAuth Request Body Hash 1.0 Draft 4}[http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/drafts/4/spec.html,
  #                                                 http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/oauth-bodyhash.html#when_to_include]
  def oauth!(http, consumer = nil, token = nil, options = {})
    helper_options = oauth_helper_options(http, consumer, token, options)
    puts helper_options.inspect
    @oauth_helper = OAuth::Client::Helper.new(self, helper_options)
    @oauth_helper.amend_user_agent_header(self)
    @oauth_helper.hash_body if oauth_body_hash_required?
    self.send("set_oauth_#{helper_options[:scheme]}")
  end

  # Create a string suitable for signing for an HTTP request. This process involves parameter
  # normalization as specified in the OAuth specification. The exact normalization also depends
  # on the <tt>options[:scheme]</tt> being used so this must match what will be used for the request
  # itself. The default scheme is +header+, in which the OAuth parameters as put into the +Authorization+
  # header.
  #
  # * http - Configured Net::HTTP instance
  # * consumer - OAuth::Consumer instance
  # * token - OAuth::Token instance
  # * options - Request-specific options (e.g. +request_uri+, +consumer+, +token+, +scheme+,
  #   +signature_method+, +nonce+, +timestamp+)
  #
  # See Also: {OAuth core spec version 1.0, section 5.4.1}[http://oauth.net/core/1.0#rfc.section.5.4.1],
  #           {OAuth Request Body Hash 1.0 Draft 4}[http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/drafts/4/spec.html,
  #                                                 http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/oauth-bodyhash.html#when_to_include]
  def signature_base_string(http, consumer = nil, token = nil, options = {})
    helper_options = oauth_helper_options(http, consumer, token, options)
    @oauth_helper = OAuth::Client::Helper.new(self, helper_options)
    @oauth_helper.hash_body if oauth_body_hash_required?
    @oauth_helper.signature_base_string
  end

private

  def oauth_helper_options(http, consumer, token, options)
    puts options.inspect
    { :request_uri       => oauth_full_request_uri(http,options),
      :consumer          => consumer,
      :token             => token,
      :scheme            => 'header',
      :signature_method  => nil,
      :nonce             => nil,
      :include_body_hash => true,
      :escape_token      => true,
      :timestamp         => nil }.merge(options)
  end

  def oauth_full_request_uri(http,options)
    uri = URI.parse(self.path)
    uri.host = http.address
    uri.port = http.port

    if options[:request_endpoint] && options[:site]
      is_https = options[:site].match(%r(^https://))
      uri.host = options[:site].gsub(%r(^https?://), '')
      uri.port ||= is_https ? 443 : 80
    end

    if http.respond_to?(:use_ssl?) && http.use_ssl?
      uri.scheme = "https"
    else
      uri.scheme = "http"
    end

    uri.to_s
  end

  def oauth_body_hash_required?
    !@oauth_helper.token_request? && request_body_permitted? && !content_type.to_s.downcase.start_with?("application/x-www-form-urlencoded")
  end

  def set_oauth_header
    self['Authorization'] = @oauth_helper.header
  end

  # FIXME: if you're using a POST body and query string parameters, this method
  # will move query string parameters into the body unexpectedly. This may
  # cause problems with non-x-www-form-urlencoded bodies submitted to URLs
  # containing query string params. If duplicate parameters are present in both
  # places, all instances should be included when calculating the signature
  # base string.

  def set_oauth_body
    self.set_form_data(@oauth_helper.stringify_keys(@oauth_helper.parameters_with_oauth))
    params_with_sig = @oauth_helper.parameters.merge(:oauth_signature => @oauth_helper.signature)
    self.set_form_data(@oauth_helper.stringify_keys(params_with_sig))
  end

  def set_oauth_query_string
    puts "ESCAPE?: #{@oauth_helper.escape_token?}"
    # return sorted_params unless @oauth_helper.escape_token?
    oauth_params_str = @oauth_helper.oauth_parameters.map do |k,v|
      puts "KEY: #{k}:#{v}"
      if k == 'oauth_token' && !@oauth_helper.escape_token?
        puts "in oauth token #{k}"
        [escape(k), v] * "=" if k == "oauth_token" && !@oauth_helper.escape_token?
      else
        [escape(k), escape(v)] * "="
      end
    end.join("&")
    puts "PARAMS STRING: #{oauth_params_str}"
    uri = URI.parse(path)
    if uri.query.to_s == ""
      uri.query = oauth_params_str
    else
      uri.query = uri.query + "&" + oauth_params_str
    end

    @path = uri.to_s
    puts "PATH: #{@path}"

    @path << "&oauth_signature=#{escape(oauth_helper.signature)}"
  end

  def sorted_params
    oauth_params_str = @oauth_helper.oauth_parameters
    .merge({'oauth_signature' => oauth_helper.signature})
    .sort
    .to_h
    .map do |k, v|
      puts "KEY: #{k}:#{v}"
      if k == 'oauth_token' && !@oauth_helper.escape_token?
        puts "in oauth token #{k}"
        [escape(k), v] * "=" if k == "oauth_token" && !@oauth_helper.escape_token?
      else
        [escape(k), escape(v)] * "="
      end
    end.join("&")
    puts "PARAMS STRING: #{oauth_params_str}"
    uri = URI.parse(path)
    if uri.query.to_s == ""
      uri.query = oauth_params_str
    else
      uri.query = uri.query + "&" + oauth_params_str
    end

    @path = uri.to_s
    puts "PATH: #{@path}"
    @path
  end
end
