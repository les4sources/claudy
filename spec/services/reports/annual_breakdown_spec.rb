require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les séries des deux graphes de `/reports` (issue #276). Le contrat le plus
# important n'est pas la forme des séries mais leur SOMME : un graphe qui ne
# retombe pas sur le total du tableau juste au-dessus rend la page incohérente.
RSpec.describe Reports::AnnualBreakdown do
  include FinanceBuilders

  let(:year) { 2026 }
  let!(:cheveche) { Lodging.create!(name: "La Chevêche test", show_on_reports: true) }
  let!(:hulotte) { Lodging.create!(name: "La Hulotte test", show_on_reports: true) }

  subject(:breakdown) { described_class.new(year: year) }

  def booking(lodging:, month:, price_cents:, status: "confirmed")
    Booking.create!(lodging: lodging, status: status, price_cents: price_cents,
                    from_date: Date.new(year, month, 10), to_date: Date.new(year, month, 12),
                    firstname: "Ana", lastname: "Test", email: "ana@example.com",
                    adults: 2, children: 0)
  end

  describe "#lodging_series" do
    it "rend douze valeurs par hébergement, à leur mois" do
      booking(lodging: cheveche, month: 3, price_cents: 40_000)
      booking(lodging: cheveche, month: 7, price_cents: 60_000)

      serie = breakdown.lodging_series.find { |s| s.label == cheveche.name }

      expect(serie.monthly_cents.size).to eq(12)
      expect(serie.monthly_cents[2]).to eq(40_000)
      expect(serie.monthly_cents[6]).to eq(60_000)
      expect(serie.total_cents).to eq(100_000)
    end

    it "affiche un hébergement du reporting même sans la moindre recette" do
      booking(lodging: cheveche, month: 3, price_cents: 40_000)

      expect(breakdown.lodging_series.map(&:label)).to include(hulotte.name)
      expect(breakdown.lodging_series.find { |s| s.label == hulotte.name }.total_cents).to eq(0)
    end

    it "range les réservations sans hébergement dans une part nommée" do
      booking(lodging: nil, month: 5, price_cents: 141_000)

      serie = breakdown.lodging_series.last

      expect(serie.label).to eq(described_class::UNASSIGNED_LABEL)
      expect(serie.total_cents).to eq(141_000)
    end

    it "somme exactement le total des réservations confirmées de l'année" do
      booking(lodging: cheveche, month: 2, price_cents: 33_000)
      booking(lodging: hulotte, month: 8, price_cents: 77_000)
      booking(lodging: nil, month: 11, price_cents: 12_000)

      total = Booking.where(status: "confirmed",
                            from_date: Date.new(year, 1, 1)..Date.new(year, 12, 31)).sum(:price_cents)

      expect(breakdown.lodging_total_cents).to eq(total)
      expect(breakdown.lodging_total_cents).to eq(122_000)
    end

    it "ignore les réservations non confirmées et celles d'une autre année" do
      booking(lodging: cheveche, month: 4, price_cents: 50_000, status: "pending")
      Booking.create!(lodging: cheveche, status: "confirmed", price_cents: 90_000,
                      from_date: Date.new(year - 1, 4, 10), to_date: Date.new(year - 1, 4, 12),
                      firstname: "Ana", lastname: "Test", email: "ana@example.com",
                      adults: 2, children: 0)

      expect(breakdown.lodging_total_cents).to eq(0)
    end

    it "attache la couleur à l'hébergement, pas à son rang dans la liste" do
      booking(lodging: hulotte, month: 6, price_cents: 10_000)

      color_this_year = breakdown.lodging_series.find { |s| s.label == hulotte.name }.color
      Lodging.create!(name: "Un gîte créé après coup", show_on_reports: true)
      color_next_year = described_class.new(year: year).lodging_series
                                       .find { |s| s.label == hulotte.name }.color

      expect(color_next_year).to eq(color_this_year)
    end
  end

  describe "#activity_slices" do
    it "porte les six activités, dans l'ordre" do
      expect(breakdown.activity_slices.map(&:key))
        .to eq(%i[lodgings spaces coworking kitchen bar grocery])
    end

    it "reprend le total des hébergements du tableau" do
      booking(lodging: cheveche, month: 3, price_cents: 40_000)

      expect(breakdown.activity_slices.find { |s| s.key == :lodgings }.amount_cents).to eq(40_000)
    end

    context "avec de la comptabilité" do
      let(:entity) { build_legal_entity }
      let!(:fiscal_year) { build_fiscal_year(entity, year: year) }
      let(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
      let(:bar) { build_general_account(code: "701001", name: "Bar", klass: 7, nature: "revenue") }
      let(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }

      def sale(account, amount_cents, on:)
        post_simple_entry(entity: entity, debit_account: bank, credit_account: account,
                          amount_cents: amount_cents, entry_date: on, journal: "sales",
                          label: "Vente #{account.code}")
      end

      it "compte les écritures créditrices du compte, sur l'année seulement" do
        sale(bar, 120_000, on: Date.new(year, 5, 4))
        sale(bar, 30_000, on: Date.new(year, 9, 9))
        sale(cellier, 45_000, on: Date.new(year, 6, 1))

        slices = breakdown.activity_slices.index_by(&:key)

        expect(slices[:bar].amount_cents).to eq(150_000)
        expect(slices[:grocery].amount_cents).to eq(45_000)
        expect(slices[:bar].state).to eq(:present)
      end

      it "n'attribue pas au bar les écritures d'un autre compte" do
        sale(cellier, 45_000, on: Date.new(year, 6, 1))
        bar # le compte existe, mais rien n'y est passé

        expect(breakdown.activity_slices.find { |s| s.key == :bar }).to be_missing_accounting
      end

      it "dit que l'année n'est pas encodée plutôt que d'afficher zéro" do
        bar
        cellier

        slice = breakdown.activity_slices.find { |s| s.key == :bar }

        expect(slice).to be_missing_accounting
        expect(slice.amount_cents).to eq(0)
      end

      it "distingue une vraie vente nulle d'une année non encodée" do
        # Une écriture qui s'annule : le compte a bien été mouvementé cette année.
        sale(bar, 10_000, on: Date.new(year, 3, 1))
        post_simple_entry(entity: entity, debit_account: bar, credit_account: bank,
                          amount_cents: 10_000, entry_date: Date.new(year, 3, 2),
                          journal: "sales", label: "Annulation")

        slice = breakdown.activity_slices.find { |s| s.key == :bar }

        expect(slice).not_to be_missing_accounting
        expect(slice.amount_cents).to eq(0)
      end
    end

    it "signale un compte introuvable au lieu d'afficher zéro" do
      GeneralAccount.where(code: %w[701001 701002]).find_each { |account| account.really_destroy! }

      expect(breakdown.activity_slices.find { |s| s.key == :bar }).to be_missing_account
      expect(breakdown.activity_slices.find { |s| s.key == :grocery }).to be_missing_account
    end
  end
end
