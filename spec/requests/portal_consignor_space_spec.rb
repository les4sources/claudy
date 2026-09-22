require "rails_helper"

# Epic #359, phase 2 — l'espace artisan : ses produits, l'encodage de ses
# feuilles, son historique. Et surtout ses cloisons : Eline n'atteint jamais ce
# qui est à Bruno.
RSpec.describe "Portail — espace artisan (produits et relevés)", type: :request do
  include ActiveJob::TestHelper

  let!(:eline) do
    Consignor.create!(name: "Eline", settlement_mode: "invoice", commission_percent: 20,
                      email: "eline@example.com", portal_enabled: true)
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", settlement_mode: "invoice",
                      email: "bruno@example.com", portal_enabled: true)
  end
  let(:period) { Date.current.strftime("%Y-%m") }

  def sign_in_consignor(email)
    perform_enqueued_jobs { post portal_code_path, params: { email: email, context: "consignor" } }
    code = ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
    post portal_login_path, params: { email: email, code: code }
  end

  def product_for(consignor, name:, cents:, active: true)
    item = CatalogItem.create!(name: name, channel: "craft", unit: "piece", consignor: consignor, active: active)
    item.catalog_prices.create!(active_from: Date.current - 30, public_price_cents: cents, member_price_cents: cents)
    item
  end

  def line_params(**attrs)
    { consignment_report: { consignment_report_lines_attributes: { "0" => attrs } } }
  end

  before { ActionMailer::Base.deliveries.clear }

  describe "sans session artisan" do
    it "renvoie vers la porte de l'artisan" do
      get portal_consignor_products_path
      expect(response).to redirect_to(portal_path(context: "consignor"))

      get portal_consignor_report_path(period: period)
      expect(response).to redirect_to(portal_path(context: "consignor"))
    end
  end

  context "Eline connectée" do
    before { sign_in_consignor("eline@example.com") }

    describe "le tableau de bord" do
      it "propose d'encoder une feuille et de gérer ses produits" do
        get portal_consignments_path

        expect(response.body).to include("Encoder une feuille", "Mes produits", "Mes relevés")
        expect(response.body).to include(portal_consignor_report_path(period: period))
      end

      it "affiche l'historique avec brut, commission, net et statut, et le net à recevoir" do
        last_month = Date.current.prev_month.beginning_of_month
        report = eline.consignment_reports.create!(period_month: last_month, status: "declared")
        report.consignment_report_lines.create!(label: "Savon", quantity: 2, unit_price_cents: 500)

        get portal_consignments_path

        expect(response.body).to include(report.period_label, "Déclaré")
        expect(response.body).to include("10,00", "2,00", "8,00")
      end
    end

    describe "Mes produits" do
      it "crée un article d'artisanat à son nom, avec un palier de prix daté d'aujourd'hui" do
        expect {
          post portal_consignor_products_path, params: { product: { name: "Savon", unit: "piece", price_euros: "4,50" } }
        }.to change { eline.catalog_items.craft.count }.by(1)

        item = eline.catalog_items.craft.last
        expect(item).to be_active
        price = item.current_price
        expect(price.active_from).to eq(Date.current)
        expect(price.public_price_cents).to eq(450)
        expect(price.member_price_cents).to eq(450)
        expect(response).to redirect_to(portal_consignor_products_path)
      end

      it "refuse un produit sans prix" do
        expect {
          post portal_consignor_products_path, params: { product: { name: "Savon", unit: "piece", price_euros: "" } }
        }.not_to change(CatalogItem, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "change le prix par un nouveau palier : l'ancien est clôturé la veille" do
        savon = product_for(eline, name: "Savon", cents: 400)
        old_tier = savon.catalog_prices.first

        patch portal_consignor_product_path(savon), params: { product: { name: "Savon", unit: "piece", price_euros: "5" } }

        expect(old_tier.reload.active_until).to eq(Date.current - 1)
        expect(savon.reload.current_price.public_price_cents).to eq(500)
        expect(savon.price_on(Date.current - 1).public_price_cents).to eq(400)
      end

      it "corrige en place un palier ouvert aujourd'hui même" do
        post portal_consignor_products_path, params: { product: { name: "Bol", unit: "piece", price_euros: "12" } }
        bol = eline.catalog_items.craft.find_by!(name: "Bol")

        patch portal_consignor_product_path(bol), params: { product: { name: "Bol", unit: "piece", price_euros: "15" } }

        expect(bol.catalog_prices.count).to eq(1)
        expect(bol.current_price.public_price_cents).to eq(1500)
      end

      it "retire de la vente et remet en vente, sans rien supprimer" do
        savon = product_for(eline, name: "Savon", cents: 400)

        patch toggle_active_portal_consignor_product_path(savon)
        expect(savon.reload).not_to be_active

        patch toggle_active_portal_consignor_product_path(savon)
        expect(savon.reload).to be_active
      end

      it "ne liste que ses propres produits" do
        product_for(eline, name: "Savon d'Eline", cents: 400)
        product_for(bruno, name: "Bougie de Bruno", cents: 900)

        get portal_consignor_products_path

        expect(response.body).to include("Savon d&#39;Eline")
        expect(response.body).not_to include("Bougie de Bruno")
      end

      it "ne laisse ni voir ni toucher les produits de Bruno" do
        bougie = product_for(bruno, name: "Bougie", cents: 900)

        expect { get edit_portal_consignor_product_path(bougie) }.to raise_error(ActiveRecord::RecordNotFound)
        expect {
          patch portal_consignor_product_path(bougie), params: { product: { name: "Volée", unit: "piece", price_euros: "1" } }
        }.to raise_error(ActiveRecord::RecordNotFound)
        expect { patch toggle_active_portal_consignor_product_path(bougie) }.to raise_error(ActiveRecord::RecordNotFound)

        expect(bougie.reload.name).to eq("Bougie")
        expect(bougie).to be_active
      end
    end

    describe "Encoder une feuille" do
      it "affiche le formulaire du mois sans créer de relevé" do
        product_for(eline, name: "Savon", cents: 450)

        expect { get portal_consignor_report_path(period: period) }.not_to change(ConsignmentReport, :count)
        expect(response.body).to include("Mes ventes de", "Savon", "Payé par", "N° des feuilles")
      end

      it "crée le relevé du mois à la première ligne, directement déclaré" do
        savon = product_for(eline, name: "Savon", cents: 450)

        expect {
          patch portal_consignor_report_path(period: period),
                params: line_params(catalog_item_id: savon.id, quantity: "2", payment_method: "cash")
                          .deep_merge(consignment_report: { sheet_numbers: "7" })
        }.to change { eline.consignment_reports.count }.by(1)

        report = eline.consignment_reports.last
        expect(report).to be_declared
        expect(report.declared_at).to be_present
        expect(report.sheet_numbers).to eq("7")
        line = report.consignment_report_lines.first
        expect(line.label).to eq("Savon")
        expect(line.unit_price_cents).to eq(450)
        expect(line.amount_cents).to eq(900)
        expect(line.payment_method).to eq("cash")
        expect(response).to redirect_to(portal_consignor_report_path(period: period))
      end

      it "garde un libellé libre pour « autre » et un prix modifié à la main" do
        patch portal_consignor_report_path(period: period),
              params: line_params(label: "Carte postale", quantity: "3", unit_price_euros: "1,50", payment_method: "qr")

        line = eline.consignment_reports.last.consignment_report_lines.first
        expect(line.catalog_item).to be_nil
        expect(line.label).to eq("Carte postale")
        expect(line.amount_cents).to eq(450)
      end

      it "ne crée rien sans aucune ligne" do
        expect {
          patch portal_consignor_report_path(period: period), params: { consignment_report: { notes: "rien" } }
        }.not_to change(ConsignmentReport, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "ajoute une seconde feuille au même relevé du mois" do
        patch portal_consignor_report_path(period: period), params: line_params(label: "Savon", quantity: "1", unit_price_euros: "4")
        patch portal_consignor_report_path(period: period), params: line_params(label: "Bol", quantity: "1", unit_price_euros: "12")

        expect(eline.consignment_reports.count).to eq(1)
        expect(eline.consignment_reports.last.consignment_report_lines.map(&:label)).to contain_exactly("Savon", "Bol")
      end

      it "refuse une ligne pointant sur un produit de Bruno" do
        bougie = product_for(bruno, name: "Bougie", cents: 900)

        patch portal_consignor_report_path(period: period), params: line_params(catalog_item_id: bougie.id, quantity: "1")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ConsignmentReportLine.where(catalog_item_id: bougie.id)).to be_empty
      end

      it "n'ouvre pas un mois passé sans relevé" do
        old = Date.current.prev_month.strftime("%Y-%m")
        expect { get portal_consignor_report_path(period: old) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "ne touche jamais au relevé de Bruno, même au même mois" do
        brunos = bruno.consignment_reports.create!(period_month: Date.current.beginning_of_month, status: "declared")
        brunos_line = brunos.consignment_report_lines.create!(label: "Bougie", quantity: 1, unit_price_cents: 900)

        # Une ligne de Bruno glissée dans le formulaire d'Eline : les attributs
        # imbriqués ne trouvent pas la ligne dans SON relevé.
        expect {
          patch portal_consignor_report_path(period: period),
                params: line_params(id: brunos_line.id, label: "Volée", quantity: "1", unit_price_euros: "0")
        }.to raise_error(ActiveRecord::RecordNotFound)
        expect(brunos_line.reload.label).to eq("Bougie")
      end

      it "affiche un relevé vérifié en lecture seule et refuse de le modifier" do
        report = eline.consignment_reports.create!(period_month: Date.current.beginning_of_month, status: "verified")
        line = report.consignment_report_lines.create!(label: "Savon", quantity: 1, unit_price_cents: 400)

        get portal_consignor_report_path(period: period)
        expect(response.body).to include("n'est plus modifiable")
        expect(response.body).not_to include("Enregistrer mes ventes")

        patch portal_consignor_report_path(period: period),
              params: line_params(id: line.id, label: "Savon", quantity: "9", unit_price_euros: "4")
        expect(response).to have_http_status(:unprocessable_entity)
        expect(line.reload.quantity).to eq(1)
      end
    end
  end

  describe "le lien mensuel à jeton" do
    it "réutilise le même formulaire de lignes, avec les produits de l'artisan" do
      product_for(eline, name: "Savon", cents: 450)
      report = eline.consignment_reports.create!(period_month: Date.current.beginning_of_month)

      get public_consignment_report_path(report.token)

      expect(response.body).to include("Payé par", "Savon", "Autre (je l&#39;écris)")
    end

    it "enregistre l'article et le mode de paiement" do
      savon = product_for(eline, name: "Savon", cents: 450)
      report = eline.consignment_reports.create!(period_month: Date.current.beginning_of_month)

      patch public_consignment_report_path(report.token),
            params: line_params(catalog_item_id: savon.id, quantity: "1", payment_method: "transfer")

      line = report.reload.consignment_report_lines.first
      expect(line.catalog_item).to eq(savon)
      expect(line.payment_method).to eq("transfer")
      expect(line.unit_price_cents).to eq(450)
    end
  end
end
