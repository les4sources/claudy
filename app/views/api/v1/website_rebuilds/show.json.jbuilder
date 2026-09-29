json.data { json.partial! "api/v1/website_rebuilds/website_rebuild", website_rebuild: @website_rebuild }
json.meta { json.webhook_configured WebsiteRebuildJob.webhook_configured? }
