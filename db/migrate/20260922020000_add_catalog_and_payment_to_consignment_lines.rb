# Epic #359, phase 1 — une ligne de relevé peut pointer un article du catalogue
# et dire comment le client a payé.
#
# Les deux colonnes sont nullables : les lignes déjà déclarées gardent leur
# libellé libre, et le lien mensuel à jeton (epic #248) continue de fonctionner
# sans article ni mode de paiement.
class AddCatalogAndPaymentToConsignmentLines < ActiveRecord::Migration[8.1]
  def change
    add_reference :consignment_report_lines, :catalog_item,
                  null: true, index: { name: "index_consignment_lines_on_catalog_item" },
                  foreign_key: true
    add_column :consignment_report_lines, :payment_method, :string
  end
end
