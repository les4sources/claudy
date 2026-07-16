require "rails_helper"

# Issue #52 — `Payment` a une clé primaire UUID, incompatible avec la table
# `versions` partagée (`item_id bigint`) : aucune version n'était enregistrée
# (trou d'auditabilité, principe P2 de l'ISA). On isole Payment dans une table
# dédiée `payment_versions` (`item_id uuid`) via `PaymentVersion`.
#
# Ce spec prouve les DEUX moitiés du correctif :
#   1. Payment est de nouveau audité (create + update + soft-delete) ;
#   2. les versions des AUTRES modèles (table `versions` partagée) restent
#      intactes et requêtables.
RSpec.describe "Payment — auditabilité PaperTrail (issue #52)", type: :model do
  let(:customer) { Customer.create!(email: "audit@example.com", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 total_amount_cents: 10_000)
  end

  describe "Payment est de nouveau audité (via PaymentVersion)" do
    it "enregistre une version à la création puis à la modification" do
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "pending",
                                payment_method: "card")

      expect(payment.versions.count).to eq(1)
      expect(payment.versions.last.event).to eq("create")

      payment.update!(status: "paid")

      expect(payment.versions.count).to eq(2)
      expect(payment.versions.last.event).to eq("update")
    end

    it "relie la version au Payment par son UUID, dans la table dédiée" do
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "pending",
                                payment_method: "card")

      version = payment.versions.last
      expect(version).to be_a(PaymentVersion)
      expect(version.item_id).to eq(payment.id) # l'UUID réel, plus le 0 du cast raté
      expect(version.class.table_name).to eq("payment_versions")
    end

    it "trace aussi le soft-delete (update de deleted_at)" do
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "pending",
                                payment_method: "card")

      expect { payment.soft_delete! }.to change { payment.versions.count }.by(1)
    end
  end

  describe "les versions des autres modèles sont préservées" do
    it "n'écrit aucune version Payment dans la table `versions` partagée" do
      before_count = PaperTrail::Version.where(item_type: "Payment").count

      Payment.create!(stay: stay, amount_cents: 5_000, status: "pending",
                      payment_method: "card")

      expect(PaperTrail::Version.where(item_type: "Payment").count).to eq(before_count)
    end

    it "continue de versionner les autres modèles dans `versions` (Booking)" do
      booking = Booking.create!(firstname: "Audit", from_date: Date.today,
                                to_date: Date.today + 2, adults: 1, status: "pending",
                                price_cents: 10_000)

      expect(booking.versions.count).to be >= 1
      expect(booking.versions.last).to be_a(PaperTrail::Version)
      expect(booking.versions.last.class.table_name).to eq("versions")

      expect { booking.update!(status: "confirmed") }
        .to change { booking.versions.count }.by(1)
    end
  end
end
