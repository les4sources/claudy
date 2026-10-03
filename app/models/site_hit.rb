# Une page vue ou un événement sur le site www.les4sources.be (statistiques
# sans cookie, 2026-10-03). Écrit par `SiteHitsController` pour le
# site et par le funnel `/reservation` pour ses étapes ; lu par
# `SiteStats::Report`.
#
# `kind` vaut « pageview » ou « event ». Les événements portent un `name` :
#   - reservation, tally, telephone, email, outbound — clics sur le site ;
#   - tally_submit — formulaire Tally envoyé depuis le site ;
#   - not_found — page 404 affichée ;
#   - funnel_dates, funnel_contact, funnel_request — étapes du funnel Claudy.
# == Schema Information
#
# Table name: site_hits
#
#  id            :bigint           not null, primary key
#  browser       :string
#  country       :string
#  day           :date             not null
#  device        :string
#  kind          :string           not null
#  name          :string
#  occurred_at   :datetime         not null
#  os            :string
#  path          :string           not null
#  referrer_host :string
#  source        :string
#  target        :string
#  utm_campaign  :string
#  utm_medium    :string
#  utm_source    :string
#  visitor_hash  :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_site_hits_on_day_and_visitor_hash  (day,visitor_hash)
#  index_site_hits_on_kind_and_name         (kind,name)
#  index_site_hits_on_occurred_at           (occurred_at)
#
class SiteHit < ApplicationRecord
  KINDS = %w[pageview event].freeze
  SITE_EVENTS = %w[reservation tally telephone email outbound tally_submit not_found].freeze
  FUNNEL_EVENTS = %w[funnel_dates funnel_contact funnel_request].freeze
  EVENTS = (SITE_EVENTS + FUNNEL_EVENTS).freeze

  validates :kind, inclusion: { in: KINDS }
  validates :name, inclusion: { in: EVENTS }, if: -> { kind == "event" }
  validates :path, :visitor_hash, :occurred_at, :day, presence: true

  scope :pageviews, -> { where(kind: "pageview") }
  scope :events, ->(*names) { where(kind: "event", name: names.flatten) }
  scope :between, ->(from, to) { where(day: from..to) }
end
