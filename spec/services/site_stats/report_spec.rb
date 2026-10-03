require "rails_helper"

# Statistiques du site sans cookie (2026-10-03) — les calculs du tableau de bord.
RSpec.describe SiteStats::Report do
  let(:today) { Date.new(2026, 10, 3) }

  def hit(visitor, path, kind: "pageview", name: nil, at: today.in_time_zone.change(hour: 10), **attrs)
    SiteHit.create!(visitor_hash: visitor, path: path, kind: kind, name: name,
                    occurred_at: at, day: at.to_date, device: "Mobile", browser: "Safari", os: "iOS",
                    country: "BE", **attrs)
  end

  before do
    # Visite A : Google, trois pages, clic Réserver puis demande envoyée.
    hit("a", "/", source: "Google", at: today.in_time_zone.change(hour: 9))
    hit("a", "/sejours", at: today.in_time_zone.change(hour: 9, min: 5))
    hit("a", "/sejours/tarifs", at: today.in_time_zone.change(hour: 9, min: 8))
    hit("a", "/sejours/tarifs", kind: "event", name: "reservation", target: "https://app.les4sources.be/reservation")
    hit("a", "/reservation/sejour", kind: "event", name: "funnel_dates")
    hit("a", "/reservation/coordonnees", kind: "event", name: "funnel_contact")
    hit("a", "/reservation/coordonnees", kind: "event", name: "funnel_request")
    # Visite B : accès direct, une seule page (rebond), sur ordinateur en France.
    hit("b", "/agenda", source: "Accès direct", device: "Ordinateur", country: "FR")
    # Demande C sans visite du site.
    hit("c", "/reservation/coordonnees", kind: "event", name: "funnel_request")
    # Hors période.
    hit("z", "/", source: "Google", at: (today - 40).in_time_zone)
  end

  subject(:report) { described_class.new(period: "7", today: today) }

  it "compte visites, pages vues, pages par visite et rebond" do
    expect(report.visits).to eq(2)
    expect(report.pageviews).to eq(4)
    expect(report.pages_per_visit).to eq(2.0)
    expect(report.bounce_rate).to eq(50)
    expect(report.requests).to eq(2)
  end

  it "range les visites par page d'arrivée et par source" do
    expect(report.entry_pages).to contain_exactly({ label: "/", visits: 1 }, { label: "/agenda", visits: 1 })
    expect(report.sources).to contain_exactly({ label: "Google", visits: 1 }, { label: "Accès direct", visits: 1 })
    expect(report.top_pages).to contain_exactly({ label: "/", visits: 1, pageviews: 1 }, { label: "/sejours", visits: 1, pageviews: 1 },
                                               { label: "/sejours/tarifs", visits: 1, pageviews: 1 }, { label: "/agenda", visits: 1, pageviews: 1 })
  end

  it "suit l'entonnoir et attribue les demandes à la source de la visite" do
    expect(report.funnel.map { |step| step[:count] }).to eq([2, 1, 1, 1, 2])
    expect(report.requests_by_source).to contain_exactly({ label: "Google", count: 1 }, { label: "Sans visite du site", count: 1 })
  end

  it "répartit appareils et pays en part des visites" do
    expect(report.devices).to contain_exactly({ label: "Mobile", visits: 1, share: 50 }, { label: "Ordinateur", visits: 1, share: 50 })
    expect(report.countries.map { |row| row[:label] }).to contain_exactly("Belgique", "France")
  end

  it "remplit chaque jour de la période, même sans visite" do
    expect(report.daily.size).to eq(7)
    expect(report.daily.last).to eq(day: today, visits: 2, pageviews: 4)
    expect(report.daily.first[:pageviews]).to eq(0)
  end

  it "compare à la période précédente et retombe sur 30 jours pour une période inconnue" do
    expect(report.change(:visits)).to be_nil
    expect(described_class.new(period: "n'importe quoi", today: today).period).to eq("30")
  end
end
