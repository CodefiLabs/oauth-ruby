require 'oauth/signature/base'

module OAuth::Signature::HMAC
  class SHA1 < OAuth::Signature::Base
    implements 'hmac-sha1'

    def body_hash
      Base64.encode64(OpenSSL::Digest::SHA1.digest(request.body || '')).chomp.gsub(/\n/,'')
    end

    private

    def digest
      puts "DIGEST: #{secret}, #{signature_base_string}"
      result = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha1'), secret, signature_base_string)
      puts "DIGEST RESULT: #{result}"
      result
    end
  end
end
