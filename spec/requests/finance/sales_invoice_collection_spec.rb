require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 6 — encaisser une facture de vente depuis « À affecter ».
#
# La facture part chez le client, l'argent arrive sur le Triodos, et rien ne
# relie les deux : la facture reste « émise » indéfiniment, même payée.
#
# Le rapprochement NE CHANGE PAS la comptabilité des recettes : il ventile le
# séjour exactement comme le fait déjà « Ventiler ce séjour ». Aucune écriture
# de vente n'est générée (décision 8) — seul le `document` des allocations
# change, et c'est lui qui fait basculer la facture en « payée ».
RSpec.describe "Comptabilité — encaisser une facture de vente (epic #240, phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-encaissement@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:customer) { Customer.create!(first_name: "Camille", last_name: "Renard", email: "camille@example.org") }
  let!(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 1), departure_date: Date.new(2026, 6, 4),
                 total_amount_cents: 130_000, invoice_status: "sent")
  end

  let(:invoice) do
    facture = SalesInvoice.create!(legal_entity: entity, customer: customer, number: "2026-100",
                                   issued_on: Date.new(2026, 6, 10), total_cents: 130_000)
    facture.sales_invoice_sources.create!(source: stay)
    facture
  end

  def entrante(cents = 130_000, iban: nil, date: Date.new(2026, 6, 15))
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Virement Renard")
    entry.update!(counterparty_iban: iban, counterparty_name: "RENARD CAMILLE") if iban
    entry
  end

  before { sign_in user }

  # Le devis reconstruit du séjour, stubbé comme dans `ventilate_stay_spec` :
  # deux moteurs de prix ont coexisté dans l'application, et le devis ne sert
  # que de PROPORTIONS — la base reste l'argent reçu.
  def stub_quote(lodging:, meals: 0)
    hebergement = build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue")
    repas = build_general_account(code: "700200", name: "Repas", klass: 7, nature: "revenue")
    RevenueMapping.find_or_create_by!(category: "lodging") { |m| m.general_account = hebergement }
    RevenueMapping.find_or_create_by!(category: "meals") { |m| m.general_account = repas }

    quote = instance_double(PricingModel::Quote, lodging_only_cents: lodging, spaces_cents: 0,
                                                 meals_cents: meals, camping_cents: 0, van_cents: 0,
                                                 terrace_cents: 0, hamac_cents: 0, experiences_cents: 0)
    allow(Stays::DraftReconstructor).to receive(:call).with(stay).and_return(:draft)
    allow(PricingModel).to receive(:quote).with(:draft).and_return(quote)
  end

  describe "Finance::MatchSalesInvoices" do
    it "propose la facture dont le montant correspond exactement" do
      invoice

      matches = Finance::MatchSalesInvoices.new.for_entry(entrante)

      expect(matches.first.invoice).to eq(invoice)
      expect(matches.first.confidence).to eq(80)
      expect(matches.first.reason).to include("2026-100")
    end

    # `customer_bank_accounts` mémorise, à chaque ventilation de séjour, le
    # compte depuis lequel un client a payé : le deuxième virement se reconnaît
    # tout seul.
    it "propose la facture d'un client reconnu par son IBAN appris" do
      invoice
      CustomerBankAccount.remember!(customer: customer, iban: "BE68539007547034", holder_name: "RENARD")

      matches = Finance::MatchSalesInvoices.new.for_entry(entrante(99_900, iban: "BE68 5390 0754 7034"))

      expect(matches.first.invoice).to eq(invoice)
      expect(matches.first.confidence).to eq(70)
    end

    # Une facture déjà payée proposée une seconde fois, c'est inviter à
    # l'encaisser deux fois.
    it "ne propose jamais une facture déjà payée" do
      invoice.update!(status: "paid", paid_on: Date.current)

      expect(Finance::MatchSalesInvoices.new.for_entry(entrante)).to be_empty
    end

    it "ne propose rien sur une ligne sortante" do
      invoice
      sortante = build_cash_entry(compte_bancaire, amount_cents: -130_000, label: "Virement émis")

      expect(Finance::MatchSalesInvoices.new.for_entry(sortante)).to be_empty
    end

    it "ne propose rien sur une ligne déjà affectée" do
      invoice
      entry = entrante
      entry.cash_allocations.create!(general_account: banque, legal_entity: entity, amount_cents: 130_000)

      expect(Finance::MatchSalesInvoices.new.for_entry(entry.reload)).to be_empty
    end

    it "rend un hash indexé par ligne dans for_entries" do
      invoice
      avec = entrante
      sans = entrante(12_345)

      resultat = Finance::MatchSalesInvoices.new.for_entries([avec, sans])

      expect(resultat.keys).to eq([avec.id])
    end
  end

  describe "Finance::RecordSalesInvoicePayment" do
    it "refuse une ligne sortante" do
      sortante = build_cash_entry(compte_bancaire, amount_cents: -130_000, label: "Virement émis")

      expect { described_service(sortante).run! }
        .to raise_error(Finance::RecordSalesInvoicePayment::WrongDirection, /ligne ENTRANTE/)
    end

    it "refuse une facture déjà payée" do
      invoice.update!(status: "paid", paid_on: Date.current)

      expect { described_service(entrante).run! }
        .to raise_error(Finance::RecordSalesInvoicePayment::AlreadyPaid)
    end

    # `VentilateStay` ne sait ventiler qu'un séjour : une facture qui n'en
    # facture aucun le dit, plutôt que d'inventer une ventilation.
    it "refuse une facture sans séjour à ventiler" do
      facture = SalesInvoice.create!(legal_entity: entity, number: "2026-200",
                                     issued_on: Date.current, total_cents: 130_000)

      expect do
        Finance::RecordSalesInvoicePayment.new(sales_invoice: facture, cash_entry: entrante).run!
      end.to raise_error(Finance::RecordSalesInvoicePayment::NoVentilableSource, /ne facture aucun séjour/)
    end

    def described_service(entry)
      Finance::RecordSalesInvoicePayment.new(sales_invoice: invoice, cash_entry: entry)
    end
  end

  describe "le geste complet" do
    # LA voie nominale : la ligne se ventile en recettes comme aujourd'hui, les
    # allocations portent la FACTURE, la facture passe payée, et l'IBAN est
    # appris pour le prochain virement de ce client.
    it "ventile la recette, solde la facture et apprend l'IBAN" do
      stub_quote(lodging: 100_000, meals: 30_000)
      entry = entrante(130_000, iban: "BE68539007547034")

      lignes = Finance::RecordSalesInvoicePayment.new(sales_invoice: invoice, cash_entry: entry).run!

      expect(lignes.size).to eq(2)
      allocations = entry.reload.cash_allocations
      expect(allocations.sum(:amount_cents)).to eq(130_000)
      # LA FACTURE en document, pas le séjour : c'est ce lien qui la solde.
      expect(allocations.map(&:document).uniq).to eq([invoice])
      expect(invoice.reload.status).to eq("paid")
      expect(invoice.paid_on).to eq(entry.entry_date)
      expect(CustomerBankAccount.customers_for("BE68539007547034")).to include(customer)
    end

    # Décision 8 : la recette est comptabilisée UNE fois, par la ventilation.
    # Une écriture de vente en plus la compterait deux fois.
    it "ne génère AUCUNE écriture de vente" do
      stub_quote(lodging: 130_000)
      entry = entrante

      Finance::RecordSalesInvoicePayment.new(sales_invoice: invoice, cash_entry: entry).run!

      expect(JournalEntry.where(journal: "sales")).to be_empty
      expect(JournalEntry.where(source: invoice)).to be_empty
    end

    it "comptabilise la ligne bancaire une fois entièrement affectée" do
      stub_quote(lodging: 130_000)
      entry = entrante

      Finance::RecordSalesInvoicePayment.new(sales_invoice: invoice, cash_entry: entry).run!

      expect(entry.reload.status).to eq("allocated")
      expect(entry.journal_entry).to be_present
    end

    it "encaisse depuis l'écran, avec un notice" do
      stub_quote(lodging: 130_000)
      entry = entrante

      post collect_sales_invoice_finance_cash_entry_path(entry, sales_invoice_id: invoice.id)

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      expect(flash[:notice]).to include("2026-100")
      expect(invoice.reload.status).to eq("paid")
    end
  end

  describe "POST collect_sales_invoice" do
    it "redirige avec une alerte quand la ligne est sortante" do
      sortante = build_cash_entry(compte_bancaire, amount_cents: -130_000, label: "Virement émis")

      post collect_sales_invoice_finance_cash_entry_path(sortante, sales_invoice_id: invoice.id)

      expect(response).to redirect_to(finance_cash_entry_path(sortante))
      expect(flash[:alert]).to include("ligne ENTRANTE")
      expect(invoice.reload.status).to eq("issued")
    end

    it "redirige avec une alerte quand le devis du séjour est vide" do
      # Un séjour sans composition ne produit aucune ventilation : le service
      # le dit, il n'invente pas de lignes.
      post collect_sales_invoice_finance_cash_entry_path(entrante, sales_invoice_id: invoice.id)

      expect(response).to redirect_to(finance_cash_entry_path(CashEntry.last))
      expect(flash[:alert]).to be_present
    end
  end

  describe "SalesInvoices::RefreshPayment" do
    # Le paiement est un RAPPROCHEMENT (décision 4) : on constate que les
    # allocations couvrent le total, on ne coche pas une case.
    it "passe la facture en payée quand les allocations couvrent son total" do
      entry = entrante
      entry.cash_allocations.create!(general_account: banque, legal_entity: entity,
                                     document: invoice, amount_cents: 130_000)

      expect(invoice.reload.status).to eq("paid")
      expect(invoice.paid_on).to eq(entry.entry_date)
    end

    it "laisse la facture émise sur un encaissement partiel" do
      entry = entrante(60_000)
      entry.cash_allocations.create!(general_account: banque, legal_entity: entity,
                                     document: invoice, amount_cents: 60_000)

      expect(invoice.reload.status).to eq("issued")
    end

    # Un état qui ne sait que monter est un état faux.
    it "ramène la facture à « émise » quand on défait l'affectation" do
      entry = entrante
      allocation = entry.cash_allocations.create!(general_account: banque, legal_entity: entity,
                                                  document: invoice, amount_cents: 130_000)
      expect(invoice.reload.status).to eq("paid")

      allocation.destroy
      SalesInvoices::RefreshPayment.new(sales_invoice: invoice.reload).run!

      expect(invoice.reload.status).to eq("issued")
      expect(invoice.paid_on).to be_nil
    end
  end

  describe "l'écran « À affecter »" do
    it "propose la facture avec sa raison et sa confiance" do
      invoice
      entrante

      get finance_unallocated_cash_entries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Facture de vente 2026-100")
      expect(response.body).to include("Encaisser cette facture")
      expect(response.body).to include("80 % de confiance")
    end

    it "ne propose plus rien une fois la facture payée" do
      invoice.update!(status: "paid", paid_on: Date.current)
      entrante

      get finance_unallocated_cash_entries_path

      expect(response.body).not_to include("Encaisser cette facture")
    end
  end
end
