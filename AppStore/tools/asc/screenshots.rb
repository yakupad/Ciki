require_relative "asc"
require "digest"
VERSIONS = { "IOS" => "6a372b38-8d3f-402e-b7bd-92abe61cedc6", "MAC_OS" => "2d46be24-46d5-4113-88be-5815e83a8d6d" }
DIR = File.expand_path("~/Projects/Ciki/AppStore/screenshots")
# Klasör → (platform sürümü, App Store Connect ekran tipi)
TYPES = {
  "iPhone-6.9" => ["IOS", "APP_IPHONE_67"],
  "iPhone-6.3" => ["IOS", "APP_IPHONE_61"],
  "iPad-13" => ["IOS", "APP_IPAD_PRO_3GEN_129"],
  "Watch" => ["IOS", "APP_WATCH_ULTRA"],
  "Mac" => ["MAC_OS", "APP_DESKTOP"],
}
only = ARGV.empty? ? TYPES.keys : ARGV

def upload(set_id, path)
  data = File.binread(path)
  shot = ASC.post("/v1/appScreenshots", { data: { type: "appScreenshots",
    attributes: { fileName: File.basename(path), fileSize: data.bytesize },
    relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } } } } })["data"]
  shot["attributes"]["uploadOperations"].each do |op|
    uri = URI(op["url"])
    req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
    op["requestHeaders"].each { |h| req[h["name"]] = h["value"] }
    req.body = data.byteslice(op["offset"], op["length"])
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "yükleme parçası #{res.code}" unless res.code.start_with?("2")
  end
  ASC.patch("/v1/appScreenshots/#{shot["id"]}", { data: { type: "appScreenshots", id: shot["id"],
    attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) } } })
  shot["id"]
end

%w[tr en-US].each do |locale|
  VERSIONS.each do |platform, version|
    loc = ASC.get("/v1/appStoreVersions/#{version}/appStoreVersionLocalizations")["data"].find { |l| l["attributes"]["locale"] == locale }
    sets = ASC.get("/v1/appStoreVersionLocalizations/#{loc["id"]}/appScreenshotSets")["data"].to_h { |s| [s["attributes"]["screenshotDisplayType"], s["id"]] }
    TYPES.each do |folder, (p, type)|
      next unless p == platform && only.include?(folder)
      files = Dir["#{DIR}/#{locale}/#{folder}/*.jpg"].sort
      next if files.empty?
      set = sets[type] || ASC.post("/v1/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: type },
        relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc["id"] } } } } })["data"]["id"]
      # Yeniden çalıştırılabilir: setteki eski görüntüler silinir.
      ASC.get("/v1/appScreenshotSets/#{set}/appScreenshots")["data"].each { |s| ASC.delete("/v1/appScreenshots/#{s["id"]}") }
      files.each { |f| upload(set, f) }
      puts "✓ #{locale} #{folder} (#{type}): #{files.size}"
    end
  end
end
