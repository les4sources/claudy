# Un palier de prix dit chez qui l'article a été acheté à ce prix-là.
#
# Le fournisseur vit sur le PALIER et pas sur l'article : on change de
# fournisseur d'une facture à l'autre (les noix viennent d'Agricovert, le
# tournesol tantôt d'Agricovert, tantôt d'Interbio), et chaque prix d'achat doit
# pouvoir se relire avec sa source. La liste est celle des tiers de la
# comptabilité, jamais une liste parallèle.
#
# Nullable : les paliers repris du fichier Excel du cellier et les prix saisis
# sans facture n'ont pas de fournisseur connu.
class AddThirdPartyToCatalogPrices < ActiveRecord::Migration[8.1]
  def change
    add_reference :catalog_prices, :third_party, null: true, index: true, foreign_key: true
  end
end
