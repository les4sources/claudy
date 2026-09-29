json.data @website_rebuilds do |website_rebuild|
  json.partial! "api/v1/website_rebuilds/website_rebuild", website_rebuild: website_rebuild
end
json.meta do
  json.webhook_configured WebsiteRebuildJob.webhook_configured?
  json.window_seconds WebsiteRebuildJob::WINDOW.to_i
end
