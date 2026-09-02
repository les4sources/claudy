class AddInvoiceStatusToStays < ActiveRecord::Migration[8.1]
  # Le séjour peut désormais porter la demande de facture (Michael 2026-09-02).
  # Jusqu'ici `invoice_status` ne vivait que sur `Booking` et `SpaceBooking`, et
  # le seul chemin qui le posait (`Bookable#set_invoice_status`, via un
  # `invoice_wanted` du formulaire Booking) a disparu avec ce formulaire :
  # depuis l'epic #81 tout se saisit sur le séjour, où RIEN ne permettait plus
  # de dire « ce client veut une facture ». Les lignes encore visibles dans la
  # file de facturation viennent toutes de l'import legacy.
  #
  # Index partiel : la file ne cherche que les séjours PORTEURS d'un statut —
  # une poignée de lignes face à des milliers de séjours sans facture.
  def change
    add_column :stays, :invoice_status, :string
    add_index :stays, :invoice_status, where: "invoice_status IS NOT NULL",
                                       name: "index_stays_on_invoice_status_present"
  end
end
