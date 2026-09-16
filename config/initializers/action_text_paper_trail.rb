# Versionne les textes riches (issue #313).
#
# Depuis que la note INTERNE d'un séjour est un `ActionText::RichText`, la
# modification ne se pose plus sur `Stay` mais sur l'enregistrement de texte
# riche : sans ce versionnement, la mention « modifiée par X le Y » sous la note
# disparaîtrait en silence, et aucun test ne rougirait.
#
# `on_load(:action_text_rich_text)` plutôt qu'un `to_prepare` : le hook ne se
# déclenche qu'une fois, là où `to_prepare` rejouerait `has_paper_trail` — et
# donc ré-enregistrerait ses callbacks — à chaque rechargement en développement.
ActiveSupport.on_load(:action_text_rich_text) do
  has_paper_trail
end
