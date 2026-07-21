require "rails_helper"

# Epic #126, Phase 1 — packs de coworking.
RSpec.describe CoworkingPack, type: :model do
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }

  def pack(attrs = {})
    CoworkingPack.create!({ customer: customer, days_total: 5, payment_method: "card" }.merge(attrs))
  end

  it "prend le prix du barème et une validité de 12 mois" do
    p = pack
    expect(p.price_cents).to eq(8_000)
    expect(p.expires_at.to_date).to eq(p.purchased_at.to_date + 12.months)
  end

  it "n'accepte que les tailles de pack du barème" do
    expect(CoworkingPack.new(customer: customer, days_total: 3, payment_method: "card")).not_to be_valid
  end

  it "n'accepte que les moyens de paiement connus" do
    expect(CoworkingPack.new(customer: customer, days_total: 5, payment_method: "bitcoin")).not_to be_valid
  end

  describe "#days_remaining" do
    it "décompte les journées vivantes, pas celles annulées" do
      p = pack(days_total: 5)
      p.coworking_reservations.create!(date: Date.new(2026, 9, 7))
      r = p.coworking_reservations.create!(date: Date.new(2026, 9, 8))

      expect(p.reload.days_remaining).to eq(3)

      r.soft_delete!(validate: false)
      expect(p.reload.days_remaining).to eq(4)
    end
  end

  describe "#payment_status" do
    it "est unpaid sans paiement, pending avec un paiement en attente, paid une fois encaissé" do
      p = pack(days_total: 5)
      expect(p.payment_status).to eq("unpaid")

      pending = Payment.create!(coworking_pack: p, amount_cents: 8_000,
                                payment_method: "bank_transfer", status: "pending")
      expect(p.reload.payment_status).to eq("pending")

      pending.update!(status: "paid")
      expect(p.reload.payment_status).to eq("paid")
    end
  end

  it "sait s'il est expiré" do
    p = pack
    p.update!(expires_at: 1.day.ago)
    expect(p).to be_expired
  end

  it "trace ses modifications avec PaperTrail et se supprime en douceur" do
    p = pack
    expect { p.update!(days_total: 10) }.to change { p.versions.count }.by(1)

    p.soft_delete!(validate: false)
    expect(CoworkingPack.where(id: p.id)).to be_empty
    expect(CoworkingPack.unscoped.where(id: p.id)).to be_present
  end
end
