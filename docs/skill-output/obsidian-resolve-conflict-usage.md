# obsidian-resolve-conflict 사용 결과

> **한 줄 요약** — 충돌한 vault 를 받아 merge 커밋과 동기화된 원격/짝 클론을 생성합니다.

```
충돌한 vault  ──▶  /pkm:obsidian-resolve-conflict  ──▶  merge 커밋 + push + peer fast-forward
```

## 1. 실행한 명령

```
/pkm:obsidian-resolve-conflict [windows|wsl] [--no-push] [--no-sync-peer] [--dry-run] [--vault <path>]
```

이번 예시:

```
/pkm:obsidian-resolve-conflict wsl --dry-run --vault /home/bwyoon/para/project/obsidian-para
```

## 2. 입력

- vault: `/home/bwyoon/para/project/obsidian-para` (side `wsl`, mode `external`)
- 원격: `origin` / `main`, upstream `origin/main`
- peer: `/mnt/c/Users/bwyoon/Documents/ObsidianVault-PARA`

## 3. 결과

```
BACKUP_SHA=2d8f34444a823860ed007c0504651eb5b32afa59   (되돌릴 수 있도록 가장 먼저 출력)

preflight     .git/index.lock 없음, 진행 중 작업 없음
entry state   unmerged 0, dirty 0, ahead/behind 0/0
PEER_MATCH    no (peer origin 이 https, vault 는 ssh)
PUSH_ALLOWED  yes

해결할 충돌 없음 (ahead 0 / behind 0) — Step 4-8 미실행, 멱등 정지
```

이 실행은 충돌이 없는 상태의 **멱등 no-op 경로**입니다. class B (노트 본문) 해결 경로는
사용자 결정을 요구하므로 실제 충돌 없이 재현하지 않았습니다.
