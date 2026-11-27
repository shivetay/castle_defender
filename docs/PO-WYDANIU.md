# Po każdym wydaniu: serwer i Google Play

Lista kroków dla właścicielki po każdym wydaniu `vX.Y.Z`. Kolejność ma znaczenie:
**najpierw serwer (Supabase i VPS), dopiero potem telefony (Google Play)**. Nowy klient
nie może trafić do graczy, zanim serwer go obsłuży.

Gdzie co robisz:

| Krok | Gdzie |
|---|---|
| 1. Wydanie w GitHubie | komputer z repo (albo VPS) i przeglądarka |
| 2. Supabase | komputer z Supabase CLI i Dashboard |
| 3. Worker | **VPS** (SSH) |
| 3.3 i 5 (SQL) | Supabase → SQL Editor, liczby wpisujesz ręcznie |
| 4. Google Play | przeglądarka |
| 6. Progi wersji (SQL) | Supabase → SQL Editor, po publikacji w Play |

W każdym terminalu, w którym wykonujesz polecenia (komputer, VPS), najpierw ustaw zmienne. `export` działa
tylko w bieżącym oknie, więc po każdym nowym logowaniu przez SSH ustawiasz je od nowa. W katalogu repo,
po `git pull` na `main`:

```bash
export V=$(python3 tools/version.py current)                       # np. 0.6.0
export SIM=$(echo "$V" | awk -F. '{print $1*10000 + $2*100 + $3}')  # np. 600
export PREV=$(git tag --list 'v*' --sort=-v:refname | grep -vx "v$V" | head -1)  # poprzedni tag
echo "V=$V SIM=$SIM PREV=${PREV:-brak}"
```

`PREV=brak` oznacza pierwszy tag. Wtedy pomiń polecenia z `$PREV`: migracje i Edge Functions sprawdzasz
w Dashboardzie (Database → Migrations, Edge Functions).

Sekretów (hasło roli `verifier`, klucz wysyłania Androida, `service_role`) nie wklejasz do issue,
PR, czatu ani logów.

---

## 1. Wydanie w GitHubie

**Gdzie:** przeglądarka (GitHub → Actions) i terminal na komputerze z repo albo na VPS (tag i `git diff`).

1. **Actions → Przygotuj wydanie → Run workflow** (`patch`, `minor`, `major` albo `X.Y.Z`).
   Workflow otworzy PR „Wydanie X.Y.Z”.
2. Przejrzyj changelog w tym PR i zmerguj go.
3. Utwórz i wypchnij tag (od razu tworzy GitHub Release):

   ```bash
   git fetch origin && git tag "v$V" origin/main && git push origin "v$V"
   ```

4. **Actions → Wydanie** (przebieg z tagu) musi być zielony w całości:
   - **Testy**: CI;
   - **Debug APK**: APK w GitHub Release;
   - **Pack weryfikacji (Verifier)**: `verify_$SIM.pck` i `.sha256` w GitHub Release;
   - **AAB do Google Play**: artefakt `dunhold-$V-google-play-aab`. Ostrzeżenie „Brak sekretów”
     oznacza, że w repo brakuje sekretów klucza wysyłania i AAB nie powstał.

Co się zmieniło po stronie serwera od poprzedniego wydania:

```bash
git diff --stat "$PREV" "v$V" -- supabase/ server/verifier/
```

Puste wyjście: kroki 2 i część kroku 3 (build obrazu) możesz pominąć.

---

## 2. Supabase (projekt `castle_defender`)

### 2.1 Migracje

**Gdzie:** komputer z repo i Supabase CLI (polecenia) oraz przeglądarka (Supabase Dashboard). Nie VPS.

Nowe pliki w `supabase/migrations/` od poprzedniego tagu:

```bash
git diff --name-only --diff-filter=A "$PREV" "v$V" -- supabase/migrations/
```

Dla każdej sprawdź, czy jest już na projekcie: Dashboard → **Database → Migrations**.
Brakujące wgrywasz w kolejności nazw (timestamp), np. Supabase CLI:

```bash
supabase link --project-ref wabeqpqrllwolhsceycd
supabase db push
```

Potem:

- **Advisors** (Dashboard → Advisors → Security i Performance): bez nowych ostrzeżeń „RLS disabled”
  i „Function search_path mutable”.
- Testy RLS przechodzą w CI (job pgTAP). Na projekcie w chmurze nie uruchamiasz testów, które coś zapisują.

### 2.2 Edge Functions

**Gdzie:** komputer z repo i Supabase CLI. Nie VPS.

Zmienione funkcje od poprzedniego tagu:

```bash
git diff --name-only "$PREV" "v$V" -- supabase/functions/ | cut -d/ -f3 | sort -u
```

Wgraj każdą z listy (np. `launch_attack`):

```bash
supabase functions deploy launch_attack --project-ref wabeqpqrllwolhsceycd
```

Najpierw migracje, potem funkcje, bo funkcja może wołać nową wersję funkcji SQL.

Jeśli lista zawiera `_shared` (wspólny kod funkcji, np. sprawdzanie wersji klienta z #336), to nie jest
osobna funkcja: wgraj wtedy wszystkie funkcje, bo każda ma ten kod w swojej paczce
(`supabase functions deploy --project-ref wabeqpqrllwolhsceycd` bez nazwy wgrywa wszystkie).

---

## 3. Worker weryfikacji na VPS

Wszystko w katalogu `~/castle_defender/server/verifier` (podmień na swoją ścieżkę).

### 3.1 Kod i obraz

**Gdzie:** VPS (SSH), katalog `~/castle_defender`.

```bash
cd ~/castle_defender && git fetch origin && git checkout main && git pull origin main
cd server/verifier
```

Jeśli w kroku 1 diff pokazał zmiany w `server/verifier/` (Dockerfile, `worker.py`, `requirements.txt`):

```bash
docker compose build
```

### 3.2 Nowy pack

**Gdzie:** VPS (SSH), katalog `~/castle_defender/server/verifier`. `scp` wpisujesz na komputerze, na który pobrałaś pliki.

Z GitHub Release (wymaga `gh auth login` na VPS):

```bash
cd packs
gh release download "v$V" --repo shivetay/castle_defender --pattern "verify_$SIM.pck*" --clobber
sha256sum -c "verify_$SIM.pck.sha256"
cd ..
```

Bez `gh`: pobierz oba pliki z GitHub Release w przeglądarce i skopiuj je na VPS:

```bash
scp "verify_$SIM.pck" "verify_$SIM.pck.sha256" root@VPS:~/castle_defender/server/verifier/packs/
```

**Starych packów nie kasuj.** Ataki z poprzednich wersji gry nadal liczą się starym packiem
(`verify_<stara>.pck`).

Sprawdzenie packa (ma wypisać `sim_version=$SIM` i skończyć się kodem 0):

```bash
sed -i "s/^SIM_VERSION=.*/SIM_VERSION=$SIM/" .env
docker compose run --rm verifier verify-pack; echo "exit=$?"
```

### 3.3 Nowa wersja symulacji w bazie

**Gdzie:** przeglądarka, Supabase → SQL Editor (projekt `castle_defender`). Liczbę wpisujesz ręcznie, zmienne z terminala tu nie działają.

Dopiero gdy `verify-pack` przeszedł. Supabase → **SQL Editor** (jako `postgres`):

```sql
insert into private.sim_versions (version) values (600) on conflict (version) do nothing;  -- = $SIM
select version, supported from private.sim_versions order by version;
```

Bez tego wpisu serwer przypisuje nowym atakom starą wersję symulacji (najwyższą z tabeli), a worker
liczy je starym packiem. Wpis bez packa na VPS kończy się `FileNotFoundError` w workerze
i atakami ze statusem `failed`.

### 3.4 Restart workera

**Gdzie:** VPS (SSH), katalog `~/castle_defender/server/verifier`.

```bash
docker compose up -d --force-recreate
docker compose logs --since 5m verifier
```

W logach: `worker start id=vps-1 packs=/app/packs`, potem tylko `ok attack_id=…` albo nic (pusta
kolejka). Nie może być adresu bazy z hasłem ani JSON-a z danymi ataku.

```bash
docker compose ps                                  # kontener Up, kolumna PORTS pusta
systemctl is-enabled castle-defender-verifier      # enabled: worker wstanie po reboocie
```

---

## 4. Google Play

**Gdzie:** przeglądarka (GitHub → Actions po plik `.aab`, potem Play Console).

1. Z przebiegu **Actions → Wydanie** (tag `v$V`) pobierz artefakt `dunhold-$V-google-play-aab`
   i rozpakuj z niego plik `.aab`.
2. [Play Console](https://play.google.com/console) → **Dunhold** → **Testowanie → Test wewnętrzny**
   (albo **Test zamknięty**) → **Utwórz nową wersję** → wgraj `.aab`.
3. **Informacje o wersji**: skrót z sekcji `## [$V]` w `CHANGELOG.md`, po polsku.
4. Play Console sam sprawdza kod wersji: musi być wyższy niż w poprzednim AAB (`$SIM` rośnie
   z każdą wersją, więc błąd oznacza wgranie starego pliku).
5. Jeśli wydanie dodaje nowe dane o graczu, nową usługę zewnętrzną albo uprawnienie Androida
   (opisane w PR jako „Bezpieczeństwo”), najpierw zaktualizuj **Zasady → Bezpieczeństwo danych**
   i politykę prywatności. Bez tego Google może odrzucić wersję.
6. **Sprawdź i wdróż**, poczekaj na status „Dostępna dla testerów”.
7. Promocja do szerszego testu (zamknięty, otwarty, produkcja) dopiero po kroku 5 tej listy.

---

## 5. Sprawdzenie po wydaniu

**Gdzie:** telefon z wersją ze sklepu, potem przeglądarka (Supabase → SQL Editor).

Na telefonie z wersją ze sklepu (`Ustawienia` w grze pokazują wersję):

- start gry i połączenie z serwerem (bez komunikatu offline);
- jeden atak na gracza do końca: wynik i łup przychodzą z serwera;
- obrona: raport ataku i ewentualne ruiny.

Na serwerze, w SQL Editorze, po kilku atakach:

```sql
select * from private.verification_health;
select sim_version, verification, count(*) from public.attacks
where created_at > now() - interval '1 day' and defender_id is not null
group by 1, 2 order by 1, 2;
```

- `queue_length` rośnie i nie spada → worker nie działa (krok 3.4, logi).
- `failed_24h` > 0 → brak packa dla jakiejś wersji (`FileNotFoundError` w logach).
- `mismatch_24h` > 0 → telefon i serwer liczą bitwę inaczej. W trybie `shadow` gracze nic nie tracą,
  ale to sygnał do zgłoszenia issue (z `attack_id`, bez danych graczy).

Na koniec zamknij issues, które to wydanie domknęło.

---

## 6. Progi wersji klienta

**Gdzie:** Supabase → SQL Editor. Dopiero gdy nowa wersja jest w Play (krok 4).

Gra porównuje swój kod wersji (`$SIM`, np. 600 dla 0.6.0) z dwoma progami w `public.client_versions`
(#336, ADR 0006):

- `recommended_code`: starsza wersja dostaje okienko „Dostępna nowa wersja” z linkiem do sklepu
  (najwyżej raz na 24 h), ale gra dalej;
- `min_code`: starsza wersja ma ekran blokady i nie zagra ani online, ani offline. Serwer odrzuca jej
  zapisy zamku i Edge Functions kodem `update_required`, także w wersjach sprzed #336.

Zaraz po statusie „Dostępna dla testerów” (albo po publikacji w produkcji) podnieś rekomendację:

```sql
update public.client_versions set recommended_code = 600, updated_at = now();  -- tu $SIM
```

Po 48 h, gdy wersja jest dostępna dla wszystkich (stopniowe wdrażanie skończone), podnieś minimum.
Wartość nie może być wyższa niż wersja w sklepie, bo zablokujesz wszystkich:

```sql
update public.client_versions set min_code = 600, updated_at = now();  -- tu $SIM
select public.client_version_policy();
```

Gra pyta o progi przy starcie i po powrocie z tła (najwyżej co godzinę), a Edge Functions trzymają
minimum w pamięci do minuty.

---

## Rollback

**Gdzie:** podane w każdym wierszu: Play Console (przeglądarka), VPS (SSH) albo SQL Editor (przeglądarka).

| Problem | Co zrobić |
|---|---|
| Nowy klient psuje grę | **Play Console:** **Zatrzymaj wdrażanie** wersji; testerzy zostają na poprzedniej. Jeśli `min_code` już wskazuje tę wersję, obniż go (wiersz niżej) |
| Zbyt wysokie `min_code` (gracze bez dostępnej aktualizacji są zablokowani) | **SQL Editor:** `update public.client_versions set min_code = <poprzedni $SIM>, updated_at = now();` Gra zdejmie blokadę po „Sprawdź ponownie” |
| Worker sypie błędami | **VPS:** `systemctl stop castle-defender-verifier` (albo `docker compose stop verifier`), `VERIFIER_COMMAND=smoke` w `.env`. Kolejka czeka, joby wracają po 5 min od restartu |
| Zły pack | **SQL Editor:** wyłącz wersję: `update private.sim_versions set supported = false where version = 600;` a na **VPS** wgraj poprawny pack. Ataki ze statusem `failed` wrócą do kolejki przez `select private.requeue_verification('<attack_id>');` |
| Odciąć worker od bazy | **SQL Editor:** `alter role verifier nologin;` |
| Zła migracja | **Repo (PR):** nowa migracja naprawcza przez PR. Nie cofasz migracji ręcznie na produkcji |

Tryb weryfikacji (`shadow` / `enforce`) zmieniasz osobno (§7 #284), nie przy każdym wydaniu.
