require_relative "asc"
require_relative "screenshots_lib"
APP = "6819577900"
ROOT = File.expand_path("~/Projects/Ciki/AppStore")
LIB = JSON.parse(File.read("#{ROOT}/asset-library.json"))
FOLDERS = { "iPhone-6.9" => "APP_IPHONE_67", "iPhone-6.3" => "APP_IPHONE_61", "iPad-13" => "APP_IPAD_PRO_3GEN_129" }
only = ARGV

existing = ASC.get("/v1/apps/#{APP}/appCustomProductPages?limit=50")["data"].to_h { |p| [p["attributes"]["name"], p["id"]] }
LIB["customProductPages"].each do |cpp|
  next unless only.empty? || only.include?(cpp["id"])
  name = cpp["name"]["tr"]
  if existing[name]
    puts "• #{name} zaten var, atlanıyor"; next
  end
  locales = { "tr" => "tr", "en-US" => "en" }
  included = [{ type: "appCustomProductPageVersions", id: "${v}", relationships: { appCustomProductPageLocalizations: {
    data: locales.keys.map { |l| { type: "appCustomProductPageLocalizations", id: "${#{l}}" } } } } }]
  locales.each { |l, k| included << { type: "appCustomProductPageLocalizations", id: "${#{l}}", attributes: { locale: l, promotionalText: cpp["promotional_text"][k] } } }
  page = ASC.post("/v1/appCustomProductPages", { data: { type: "appCustomProductPages", attributes: { name: name },
    relationships: { app: { data: { type: "apps", id: APP } }, appCustomProductPageVersions: { data: [{ type: "appCustomProductPageVersions", id: "${v}" }] } } },
    included: included })["data"]
  version = ASC.get("/v1/appCustomProductPages/#{page["id"]}/appCustomProductPageVersions")["data"].first
  ASC.get("/v1/appCustomProductPageVersions/#{version["id"]}/appCustomProductPageLocalizations")["data"].each do |loc|
    locale = loc["attributes"]["locale"]
    FOLDERS.each do |folder, type|
      files = Dir["#{ROOT}/screenshots/#{locale}/#{folder}/*.jpg"]
      ordered = cpp["order"].filter_map { |s| files.find { |f| File.basename(f).sub(/^\d+-/, "").sub(".jpg", "") == s } }
      next if ordered.empty?
      set = ASC.post("/v1/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: type },
        relationships: { appCustomProductPageLocalization: { data: { type: "appCustomProductPageLocalizations", id: loc["id"] } } } } })["data"]["id"]
      ordered.each { |f| upload_screenshot(set, f) }
    end
    puts "✓ #{name} #{locale}"
  end
end
