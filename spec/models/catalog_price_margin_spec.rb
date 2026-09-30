require "rails_helper"

# Marge sur coût d'un palier : (public − achat) ÷ achat, arrondie à l'entier.
RSpec.describe CatalogPrice, "marge" do
  def price(purchase:, public_price:)
    CatalogPrice.new(active_from: Date.current, member_price_cents: 100,
                     purchase_price_cents: purchase, public_price_cents: public_price)
  end

  it "se calcule sur le prix d'achat" do
    expect(price(purchase: 200, public_price: 260).margin_percent).to eq(30)
  end

  it "est absente sans prix d'achat ou sans prix public" do
    expect(price(purchase: nil, public_price: 260).margin_percent).to be_nil
    expect(price(purchase: 200, public_price: nil).margin_percent).to be_nil
    expect(price(purchase: 0, public_price: 260).margin_level).to be_nil
  end

  it "est rouge sous 25 %, orange jusqu'à 28 %, verte au-delà" do
    expect(price(purchase: 100, public_price: 124).margin_level).to eq(:low)
    expect(price(purchase: 100, public_price: 125).margin_level).to eq(:medium)
    expect(price(purchase: 100, public_price: 127).margin_level).to eq(:medium)
    expect(price(purchase: 100, public_price: 128).margin_level).to eq(:good)
  end

  it "conseille un prix public à 30 % de marge" do
    expect(described_class.recommended_public_cents(161)).to eq(209)
    expect(described_class.recommended_public_cents(nil)).to be_nil
  end
end
