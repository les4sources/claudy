require "rails_helper"

RSpec.describe CatalogItem do
  let(:item) { described_class.create!(name: "Moinette", channel: "bar", unit: "piece") }

  describe "#price_on" do
    before do
      item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), active_until: Date.new(2026, 8, 31), member_price_cents: 200)
      item.catalog_prices.create!(active_from: Date.new(2026, 9, 1), member_price_cents: 210)
    end

    # LE critère de la phase : créer un palier au 1er septembre ne doit pas
    # déplacer le prix du 31 août, sinon un décompte déjà émis se met à mentir.
    it "résout le palier de la date demandée, sans déborder sur le suivant" do
      expect(item.price_on(Date.new(2026, 8, 31)).member_price_cents).to eq(200)
      expect(item.price_on(Date.new(2026, 9, 1)).member_price_cents).to eq(210)
    end

    it "ne résout rien avant le premier palier" do
      expect(item.price_on(Date.new(2022, 12, 31))).to be_nil
    end

    it "ne lève pas sur une date nulle" do
      expect(item.price_on(nil)).to be_nil
    end

    it "renvoie nil pour un article sans palier" do
      autre = described_class.create!(name: "Sans prix", channel: "bar")

      expect(autre.current_price).to be_nil
    end
  end

  describe "chevauchement de paliers" do
    before { item.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 200) }

    it "refuse un palier qui commence dans une période ouverte" do
      doublon = item.catalog_prices.new(active_from: Date.new(2026, 6, 1), member_price_cents: 210)

      expect(doublon).not_to be_valid
      expect(doublon.errors[:active_from]).to be_present
    end

    it "refuse une date de fin antérieure à la date de début" do
      invalide = item.catalog_prices.new(active_from: Date.new(2027, 3, 1), active_until: Date.new(2027, 1, 1), member_price_cents: 210)

      expect(invalide).not_to be_valid
    end
  end

  describe "validations" do
    it "refuse un canal inconnu" do
      expect(described_class.new(name: "X", channel: "casino")).not_to be_valid
    end

    it "refuse un palier sans prix sourcier" do
      expect(item.catalog_prices.new(active_from: Date.current)).not_to be_valid
    end
  end

  describe "scopes" do
    it "filtre par canal et par nom" do
      item
      described_class.create!(name: "Avoine bio", channel: "grocery", unit: "kg")

      expect(described_class.for_channel("grocery").map(&:name)).to eq(["Avoine bio"])
      expect(described_class.matching("moin").map(&:name)).to eq(["Moinette"])
    end
  end
end
