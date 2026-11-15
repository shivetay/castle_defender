# Widok zamku

Zamek z góry pod kątem 3/4 (top-down z widoczną przednią ścianą murów). Tylko ten rzut pokazuje jednocześnie wysokość średniowiecznych wież i gwiaździsty kształt twierdzy bastionowej.

## Siatka i skala
- Mapa 64×64 kratki, kratka 8×8 px; ekran 320×180 px, skalowany całkowicie (4× → 1280×720).
- Trzy poziomy zoomu (szczypanie): 1× cała twierdza, 2× dzielnica, 4× pojedynczy żołnierze.
- Wysokość = liczba pikseli „ściany” pod dachem: palisada 4 px, mur kamienny 10 px, donjon 24 px, bastion 6 px (niższy, szerszy).

## Seed mapy
- Każdy gracz dostaje przy pierwszym uruchomieniu własny, losowy seed terenu. Seed nie zmienia się przez całą grę (także przy zmianie epoki) i jest zapisany lokalnie oraz na serwerze (`castles.map_seed`).
- Mapa z seeda przechodzi walidację grywalności (miejsce na Dwór, droga do bramy); jeśli jej nie przejdzie, losujemy kolejny.
- Atakujący odtwarza teren obrońcy z jego seeda, więc oba widoki są identyczne. Seed terenu jest osobny od seeda bitwy. Ticket: #97.

## Warstwy renderowania (od dołu)
1. Teren: wzgórze z szumu (3–4 odcienie trawy), ścieżki, rzeka.
2. Ziemia: wały, fosy, glacis jako gradienty z ditheringiem 2×2.
3. Mury: autotiling 16 wariantów (N/E/S/W), osobno blanki i ściana.
4. Budynki: `draw_building(typ, poziom, stan)` z prymitywów (ściana, dach, okna co 3 px, belki, flaga).
5. Jednostki: ludziki 3×5 px, kolor tułowia = frakcja, 2 klatki chodu.
6. Efekty: dym, strzały (linia 1 px), kule z cieniem, pył, ogień z cząsteczek.
7. Atmosfera: pora dnia (tint), deszcz, śnieg, mgła o świcie.

## Proceduralny wygląd bez assetów
- Paleta 12–16 kolorów na epokę: I brązy i zieleń, III szarości wapienia, VI ceglana czerwień i piaskowiec.
- Faktura kamienia: szum z ziarnem `hash(x, y)`, stały dla kratki, bez powtarzalnego wzoru.
- 4 stany zniszczenia: cały, pęknięcia, wyrwa w blankach, gruz.
- Przebudowa widoczna: stare elementy zostają jako ruiny lub fundamenty pod nowymi.
- Życie w zamku: mieszkańcy, kowal, łopocząca flaga, patrole na murach.

## Tryb „Kronika” (opcjonalnie)
Animacja zmian zamku od grodu do twierdzy na podstawie historii budowy gracza. Dobry materiał do udostępniania i Google Play.

Powiązane: [[Stack technologiczny]], [[Epoki]]
