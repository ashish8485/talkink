<div align="center">

# Söyle

**Dis-le. Et c'est écrit.**

Dictée vocale push-to-talk **100 % locale** sur Apple Silicon, propulsée par
**NVIDIA Nemotron 3.5 ASR** (streaming, 40 langues) via **MLX**.
Maintiens une touche, parle, relâche — le texte est transcrit en local et prêt à coller.

</div>

---

> 🚧 **En construction.** Le moteur de transcription natif (Swift/MLX) est la première
> brique posée ; l'app menu-bar push-to-talk suit. Voir [BUILDING.md](BUILDING.md).

## Pourquoi

- **Local, privé, gratuit** — aucun audio ne quitte ta machine, pas d'abonnement.
- **Multilingue** — 40 locales depuis un seul modèle (FR/EN inclus), ponctuation + casse automatiques.
- **Rapide** — Nemotron 3.5 (600M) tourne plusieurs fois plus vite que le temps réel sur un M-series.
- **Simple** — defaults sensés pour tout le monde, réglages avancés pour qui veut.

## État

| Brique | Statut |
|---|---|
| Moteur natif Swift/MLX (`SoyleKit`) | ✅ |
| CLI / bench (`soyle-cli`) | ✅ |
| App menu-bar push-to-talk | ⏳ |
| Réglages (touche, langue, modèle 8-bit/bf16) | ⏳ |
| Packaging `.app` + Homebrew | ⏳ |

## CLI (dispo dès maintenant)

```bash
swift run -c release soyle-cli mon_audio.wav --lang fr-FR
swift run -c release soyle-cli mon_audio.wav --bf16          # précision max
swift run -c release soyle-cli mon_audio.wav --stream        # sortie incrémentale
```

## Crédits

- **NVIDIA Nemotron 3.5 ASR** — modèle (licence OpenMDW-1.1).
- **[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)** (Prince Canuma, MIT) — implémentation Swift/MLX de Nemotron.
- **[mlx-community](https://huggingface.co/mlx-community)** — poids convertis MLX (8-bit / bf16).
- **[MLX](https://github.com/ml-explore/mlx-swift)** (Apple) — framework de calcul.

## Licence

[MIT](LICENSE).
