# App Store Connect API için küçük istemci. Anahtar bilgileri ortam değişkenlerinden okunur.
require "openssl"
require "json"
require "base64"
require "net/http"
require "uri"

module ASC
  KEY_ID = ENV.fetch("ASC_KEY_ID")
  ISSUER = ENV.fetch("ASC_ISSUER_ID")
  KEY = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
  BASE = "https://api.appstoreconnect.apple.com"

  def self.b64(data) = Base64.urlsafe_encode64(data, padding: false)

  def self.token
    header = { alg: "ES256", kid: KEY_ID, typ: "JWT" }
    payload = { iss: ISSUER, iat: Time.now.to_i, exp: Time.now.to_i + 15 * 60, aud: "appstoreconnect-v1" }
    input = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
    der = KEY.sign(OpenSSL::Digest::SHA256.new, input)
    asn = OpenSSL::ASN1.decode(der)
    sig = asn.value.map { |i| i.value.to_s(2).rjust(32, "\x00") }.join
    "#{input}.#{b64(sig)}"
  end

  def self.request(method, path, body = nil)
    uri = URI(path.start_with?("http") ? path : BASE + path)
    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
    raise "#{method.upcase} #{path} → #{res.code}: #{data.dig('errors', 0, 'detail') || res.body[0, 300]}" unless res.code.start_with?("2")
    data
  end

  def self.get(path) = request(:get, path)
  def self.post(path, body) = request(:post, path, body)
  def self.patch(path, body) = request(:patch, path, body)
  def self.delete(path) = request(:delete, path)
end
