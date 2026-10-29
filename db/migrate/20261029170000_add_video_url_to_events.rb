# Vidéo publique d'un événement (bande-annonce d'une projection, captation…) :
# un lien YouTube que le site les4sources.be affiche sur la fiche.
class AddVideoUrlToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :video_url, :string
  end
end
