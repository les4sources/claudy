require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 6 — le registre des factures de vente.
#
# Claudy n'ÉMET pas de facture de vente : elles sortent d'OkiOki, qui n'a pas
# d'API. Il les enregistre, les relie à ce qu'elles facturent — c'est ce lien
# qui empêche un séjour de partir deux fois en facture — et dit lesquelles sont
# payées, par rapprochement bancaire et jamais par une case cochée.
RSpec.describe "Comptabilité — factures de vente (epic #240, phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-ventes@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:customer) { Customer.create!(first_name: "Camille", last_name: "Renard", email: "camille@example.org") }
  let!(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 1), departure_date: Date.new(2026, 6, 4),
                 total_amount_cents: 130_000, invoice_status: "requested")
  end

  before { sign_in user }

  def build_invoice(number: "2026-001", **attrs)
    SalesInvoice.create!({ legal_entity: entity, customer: customer, number: number,
                           issued_on: Date.new(2026, 6, 10), total_cents: 130_000 }.merge(attrs))
  end

  describe "le modèle" do
    it "exige un numéro, une date et un montant positif" do
      expect(SalesInvoice.new(legal_entity: entity)).not_to be_valid
      expect(SalesInvoice.new(legal_entity: entity, number: "X", issued_on: Date.current, total_cents: 0))
        .not_to be_valid
    end

    # Deux « 2026-001 » coexistent légitimement entre la fondation et la SRL :
    # le numéro OkiOki est unique PAR ENTITÉ.
    it "refuse deux fois le même numéro dans la même entité" do
      build_invoice
      doublon = SalesInvoice.new(legal_entity: entity, number: "2026-001",
                                 issued_on: Date.current, total_cents: 1_000)

      expect(doublon).not_to be_valid
    end

    it "accepte le même numéro dans une autre entité" do
      build_invoice
      autre = build_legal_entity(name: "Marco & Vespucci")

      expect(SalesInvoice.new(legal_entity: autre, number: "2026-001",
                              issued_on: Date.current, total_cents: 1_000)).to be_valid
    end

    # C'EST L'INVARIANT DE LA PHASE.
    it "refuse de rattacher deux fois la même réservation" do
      premiere = build_invoice
      premiere.sales_invoice_sources.create!(source: stay)
      seconde = build_invoice(number: "2026-002")

      lien = seconde.sales_invoice_sources.new(source: stay)

      expect(lien).not_to be_valid
      expect { lien.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "SalesInvoices::Register" do
    it "crée la facture, la relie au séjour et sort la ligne de la file" do
      service = SalesInvoices::Register.new(source: stay, legal_entity: entity, number: "2026-007",
                                            issued_on: Date.new(2026, 6, 10), total_cents: 130_000)
      service.run!

      facture = service.invoice
      expect(facture.number).to eq("2026-007")
      expect(facture.status).to eq("issued")
      expect(facture.sources).to eq([stay])
      expect(stay.reload.invoice_status).to eq("sent")
    end

    it "refuse une source déjà facturée" do
      SalesInvoices::Register.new(source: stay, legal_entity: entity, number: "2026-007",
                                  issued_on: Date.current, total_cents: 130_000).run!

      expect do
        SalesInvoices::Register.new(source: stay, legal_entity: entity, number: "2026-008",
                                    issued_on: Date.current, total_cents: 130_000).run!
      end.to raise_error(SalesInvoices::Register::AlreadyInvoiced)

      expect(SalesInvoice.count).to eq(1)
    end

    # Les deux moitiés tombent ensemble, ou pas du tout : une facture
    # enregistrée sans le passage en « envoyée » laisserait le travail à refaire.
    it "ne laisse pas de facture derrière lui quand le numéro est refusé" do
      build_invoice(number: "2026-009")

      expect do
        SalesInvoices::Register.new(source: stay, legal_entity: entity, number: "2026-009",
                                    issued_on: Date.current, total_cents: 130_000).run!
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(SalesInvoice.where(number: "2026-009").count).to eq(1)
      expect(stay.reload.invoice_status).to eq("requested")
    end
  end

  describe "la file Facturation" do
    it "propose « Enregistrer la facture » plutôt que le simple marquage" do
      get invoicing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Enregistrer la facture")
      # Le `&` de la query string est échappé dans le HTML : on compare donc
      # sur la forme échappée, pas sur celle que rend le helper.
      expect(response.body).to include(CGI.escapeHTML(new_finance_sales_invoice_path(kind: "stay", source_id: stay.id)))
    end

    it "pré-remplit le montant depuis le séjour" do
      get new_finance_sales_invoice_path(kind: "stay", source_id: stay.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1300,00")
    end

    it "signale une réservation déjà facturée" do
      SalesInvoices::Register.new(source: stay, legal_entity: entity, number: "2026-010",
                                  issued_on: Date.current, total_cents: 130_000).run!

      get new_finance_sales_invoice_path(kind: "stay", source_id: stay.id)

      expect(response.body).to include("Déjà facturé")
      expect(response.body).to include("2026-010")
    end

    it "enregistre la facture et renvoie sur la file" do
      post finance_sales_invoices_path(kind: "stay", source_id: stay.id),
           params: { sales_invoice: { legal_entity_id: entity.id, number: "2026-011",
                                      issued_on: "2026-06-10", total: "1300,00" } }

      expect(response).to redirect_to(invoicing_path)
      expect(SalesInvoice.find_by(number: "2026-011").total_cents).to eq(130_000)
      expect(stay.reload.invoice_status).to eq("sent")
    end

    it "réaffiche le formulaire avec l'erreur sur un doublon de numéro" do
      build_invoice(number: "2026-012")

      post finance_sales_invoices_path(kind: "stay", source_id: stay.id),
           params: { sales_invoice: { legal_entity_id: entity.id, number: "2026-012",
                                      issued_on: "2026-06-10", total: "1300,00" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
      expect(stay.reload.invoice_status).to eq("requested")
    end
  end

  describe "l'écran Ventes" do
    it "liste les factures avec leurs totaux" do
      build_invoice(number: "2026-020")
      build_invoice(number: "2026-021", total_cents: 50_000, status: "paid", paid_on: Date.new(2026, 7, 1))

      get finance_sales_invoices_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026-020")
      expect(response.body).to include("2026-021")
      # Le séparateur de milliers du formateur monétaire n'est pas un espace
      # ordinaire : on le laisse libre plutôt que de le deviner.
      expect(response.body).to match(/1.800\s*€/)
    end

    it "filtre par statut" do
      build_invoice(number: "2026-020")
      build_invoice(number: "2026-021", total_cents: 50_000, status: "paid")

      get finance_sales_invoices_path(status: "paid")

      expect(response.body).to include("2026-021")
      expect(response.body).not_to include("2026-020")
    end

    it "filtre par période et par numéro" do
      build_invoice(number: "2026-030", issued_on: Date.new(2026, 1, 15))
      build_invoice(number: "2026-031", issued_on: Date.new(2026, 8, 15))

      get finance_sales_invoices_path(from: "2026-06-01")
      expect(response.body).to include("2026-031")
      expect(response.body).not_to include("2026-030")

      get finance_sales_invoices_path(q: "030")
      expect(response.body).to include("2026-030")
      expect(response.body).not_to include("2026-031")
    end

    it "explique l'écran vide plutôt que de le laisser blanc" do
      get finance_sales_invoices_path

      expect(response.body).to include("Aucune facture de vente pour ce filtre")
    end

    it "montre la fiche avec le séjour facturé" do
      facture = build_invoice(number: "2026-040")
      facture.sales_invoice_sources.create!(source: stay)

      get finance_sales_invoice_path(facture)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026-040")
      expect(response.body).to include("Ce qu'elle facture")
      expect(response.body).to include(stay_path(stay))
    end

    it "pose l'entrée « Ventes » dans la sous-navigation Comptabilité" do
      get finance_sales_invoices_path

      expect(response.body).to include(">Ventes</a>")
    end
  end
end
