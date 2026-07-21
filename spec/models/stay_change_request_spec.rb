require "rails_helper"

# Issue #133 — demande de modification de séjour par le client.
RSpec.describe StayChangeRequest, type: :model do
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.current + 10, departure_date: Date.current + 12,
                 total_amount_cents: 50_000)
  end

  def request_for(stay, attrs = {})
    StayChangeRequest.new({ stay: stay, draft_snapshot: {}, new_total_cents: 50_000,
                            delta_cents: 0 }.merge(attrs))
  end

  it "n'accepte que les statuts connus" do
    expect(request_for(stay, status: "peut-être")).not_to be_valid
  end

  it "refuse un nouveau total négatif" do
    expect(request_for(stay, new_total_cents: -1)).not_to be_valid
  end

  describe "IBAN" do
    before { Payment.create!(stay: stay, amount_cents: 50_000, payment_method: "card", status: "paid") }

    it "est OBLIGATOIRE quand le client a trop payé" do
      change = request_for(stay, new_total_cents: 40_000, delta_cents: -10_000)

      expect(change).not_to be_valid
      expect(change.errors[:refund_iban]).to be_present
    end

    it "est accepté au bon format et normalisé" do
      change = request_for(stay, new_total_cents: 40_000, delta_cents: -10_000,
                                 refund_iban: "be68 5390 0754 7034")
      expect(change).to be_valid
      change.validate
      expect(change.refund_iban).to eq("BE68539007547034")
    end

    it "refuse un IBAN mal formé" do
      change = request_for(stay, new_total_cents: 40_000, delta_cents: -10_000,
                                 refund_iban: "pas-un-iban")
      expect(change).not_to be_valid
      expect(change.errors[:refund_iban]).to be_present
    end

    it "n'est PAS exigé quand le total augmente" do
      expect(request_for(stay, new_total_cents: 60_000, delta_cents: 10_000)).to be_valid
    end
  end

  it "n'autorise qu'une seule demande pending par séjour" do
    request_for(stay).save!

    duplicate = request_for(stay)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:base].join).to include("déjà en attente")
  end

  it "autorise une nouvelle demande une fois la précédente traitée" do
    first = request_for(stay)
    first.save!
    first.update!(status: "refused", refusal_reason: "Complet")

    expect(request_for(stay)).to be_valid
  end

  it "trace ses modifications et se supprime en douceur" do
    change = request_for(stay)
    change.save!

    expect { change.update!(status: "approved") }.to change { change.versions.count }.by(1)

    change.soft_delete!(validate: false)
    expect(StayChangeRequest.where(id: change.id)).to be_empty
  end

  it "reconstruit le draft proposé depuis son snapshot" do
    change = request_for(stay, draft_snapshot: { "arrival_date" => "2026-09-07",
                                                 "departure_date" => "2026-09-10" })
    expect(change.proposed_draft.arrival_date).to eq(Date.new(2026, 9, 7))
  end
end
