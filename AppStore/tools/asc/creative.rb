require_relative "asc"
require "digest"
ROOT = File.expand_path("~/Projects/Ciki/AppStore/creative")
existing = []
url = "/v1/appAssetLibraries/6819577900/images?limit=200"
while url
  r = ASC.get(url); existing += r["data"].map { |i| i["attributes"]["referenceName"] }; url = r.dig("links", "next")
end
ids = {}
%w[tr en-US].each do |locale|
  Dir["#{ROOT}/#{locale}/*.{jpg,png}"].sort.each do |path|
    ref = "#{locale}-#{File.basename(path)}"
    next puts("• #{ref} zaten var") if existing.include?(ref)
    data = File.binread(path)
    img = ASC.post("/v1/appAssetLibraryImages", { data: { type: "appAssetLibraryImages",
      attributes: { fileName: ref, fileSize: data.bytesize, category: "CREATIVE_ASSETS", referenceName: ref },
      relationships: { assetLibrary: { data: { type: "appAssetLibraries", id: "6819577900" } } } } })["data"]
    img["attributes"]["uploadOperations"].each do |op|
      uri = URI(op["url"]); req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
      op["requestHeaders"].each { |h| req[h["name"]] = h["value"] }
      req.body = data.byteslice(op["offset"], op["length"])
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
      raise "parça #{res.code}" unless res.code.start_with?("2")
    end
    ASC.patch("/v1/appAssetLibraryImages/#{img["id"]}", { data: { type: "appAssetLibraryImages", id: img["id"],
      attributes: { uploaded: true } } })
    puts "✓ #{ref}"
  end
end
