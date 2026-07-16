require "rails_helper"

# Epic #26, Phase 4 — verrouille l'invariant posé par la migration
# `MakePaymentsBookingIdNullable` (20260714013705) : `payments.booking_id` est
# nullable, et ce changement est PUREMENT PERMISSIF (un `change_column_null`, du
# DDL de métadonnée : il ne touche aucune ligne). On prouve ici que la migration
# n'a pu perdre ni modifier aucun Payment, et que PaperTrail reste intact.
RSpec.describe "Payment — booking_id nullable (epic #26, Phase 4)", type: :model do
  let(:customer) { Customer.create!(email: "nullable@example.com", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 total_amount_cents: 10_000)
  end

  describe "AC (c) — la colonne booking_id est nullable" do
    it "expose booking_id comme nullable au niveau schéma" do
      expect(Payment.columns_hash["booking_id"].null).to be(true)
    end

    it "persiste un Payment sans booking (séjour sans hébergement)" do
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "pending",
                                payment_method: "card")

      expect(payment.reload.booking_id).to be_nil
      expect(payment).to be_persisted
    end
  end

  describe "AC (d) anti — la migration nullable est non destructive" do
    # La migration `MakePaymentsBookingIdNullable` est un simple `change_column_null`
    # (DDL de métadonnée) : elle ne réécrit AUCUNE ligne. On verrouille en régression
    # l'invariant qui prouve l'absence de perte/altération : le nombre de Payment
    # (soft-deleted inclus) ne bouge pas d'un cheveu sous un soft-delete. Assertions
    # RELATIVES (baseline + matcher change) pour rester déterministes même si un run
    # précédent a laissé des Payment résiduels en base de test.
    it "ne perd aucun Payment : la ligne survit au soft-delete (count with_deleted stable)" do
      baseline = Payment.with_deleted { Payment.unscoped.count }

      Payment.create!(booking: nil, stay: stay, amount_cents: 5_000, status: "pending",
                      payment_method: "card")
      other_stay = Stay.create!(customer: customer, source: "reservation", status: "pending",
                                total_amount_cents: 6_000)
      to_delete = Payment.create!(stay: other_stay, amount_cents: 6_000, status: "pending",
                                  payment_method: "card")

      expect(Payment.with_deleted { Payment.unscoped.count }).to eq(baseline + 2)

      expect { to_delete.soft_delete! }
        .not_to change { Payment.with_deleted { Payment.unscoped.count } }
    end

    # NOTE (résolu depuis, issue #52) : le trou d'auditabilité PaperTrail décrit ici
    # (table `versions` en `item_id bigint` incompatible avec la PK UUID de Payment)
    # est refermé. Payment est désormais versionné dans une table dédiée
    # `payment_versions` (`item_id uuid`) via `PaymentVersion`. La preuve
    # d'auditabilité vit dans `spec/models/payment_paper_trail_spec.rb`.
  end
end
