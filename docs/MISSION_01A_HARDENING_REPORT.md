# IRONLINK MISSION 01A — Controlled Recovery & Hardening

تاريخ التحقق: 2026-11-04. نطاق التنفيذ: تصحيح REV-01 إلى REV-06 محلياً فقط.

## A. Executive Verdict

**READY FOR OWNER REVIEW**

أُغلقت الملاحظات الست بأدلة محلية فعلية. نجحت مجموعة Backend الكاملة: **667 passed, 0 failed, 0 skipped**، مع 7 تحذيرات deprecation. وآخر تنفيذ لمسار security gate الإلزامي على الملفات المصححة نجح: **124 passed, 0 failed, 0 skipped** خلال 209.72s. لم تُخفَ الإعادة السابقة التي انتهت بـ120 passed و4 failed: سُجلت تفاصيلها، ثم نجحت الحالات المتأثرة الخمس منفردة، ثم نجح gate بالكامل دون توسيع timeouts أو تخفيف assertions.

هذا حكم بجاهزية التغييرات للمراجعة، وليس إثباتاً لجاهزية production. تشغيل GitHub-hosted CI ونشر Render هما **NOT VERIFIED**. لم يُنفذ commit أو push أو merge أو deployment في هذه المهمة.

## B. Repository Safety

- Worktree: `C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink`.
- Branch: `codex/mission-01a-postgres-bootstrap`.
- HEAD قبل التنفيذ وبعده: `86b36769fc512b007e9173607e258306dcd5d468`.
- Implementation baseline التاريخي: `654ddb793ab06b78ff3d06f18428f1005b9986ee`.
- Remote deployment branch: `fix/boot-crashes-and-backend-merge`.
- Remote SHA قبل التنفيذ وعند التحقق النهائي: `42f881f4e92c23c99255594d9f9cc10112cffa53`، باستخدام `git ls-remote` للقراءة فقط.
- Original checkout: `D:/Projects/IronLink`، على deployment branch وHEAD `42f881f4e92c23c99255594d9f9cc10112cffa53`.

الحالة الأولية الفعلية كانت 12 modified tracked files و9 untracked files، لا العدد التاريخي 13+9. كانت قائمة casing variants واختبار shell المكرر موجودين بالفعل قبل بدء التصحيح؛ لذلك لم تُفترض مطابقة الشجرة للمراجعة السابقة. لم يُحدد صاحب هذه التعديلات أو يُفترض وجود agent نشط.

حُفظت Git status وSHA-256 لكل الملفات الـ21 الموجودة في الحالة الأولية، مع status وبصمات الملفات المعدلة وغير المتتبعة في original checkout، في:

`C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docs/MISSION_01A_HARDENING_BASELINE.json`

التحقق المقارن أكد بقاء جميع الملفات السابقة، وثبات ملفات original checkout وحالتها. لم يُستخدم reset أو clean أو stash أو rebase أو cherry-pick أو تبديل branch. لا توجد تغييرات staged. جميع ملفات المصدر والتقرير المعدلة في هذه المهمة داخل worktree المحدد.

## C. Remote Commit Assessment

فحص `git show 42f881f --format=fuller --stat --patch` أثبت أن commit يضيف سطراً واحداً إلى `render.yaml` فقط:

```yaml
preDeployCommand: python -m alembic upgrade head
```

الـBlueprint على ذلك commit يعلن `plan: free`، بينما [Render يقصر pre-deploy commands على الخدمات المؤهلة المدفوعة](https://render.com/docs/deploys#pre-deploy-command). لم تُفتح لوحة Render، ولم تُفحص خطة الخدمة الحية أو يُفترض أنها مطابقة للـYAML.

Deployment branch ينفذ بالفعل `alembic upgrade head` ثم `apply_post_migrate.py` في container startup. إن أُتيح hook على خدمة مدفوعة، فسيضيف مسار migrations ثانياً، مع تكرار التنفيذ واحتمال التداخل بين deployments؛ كما أن standalone hook لا يقدم invariant القفل المشترك الذي ينفذه bootstrap الجديد. الـworktree يحتوي تصميماً مستقلاً: bootstrap موحد ثم فحص runtime ثم إزالة credentials قبل Uvicorn.

**التوصية:** إجراء normal revert للـcommit `42f881f4e92c23c99255594d9f9cc10112cffa53` قبل دمج MISSION 01A في تصميم Free. لا force push ولا إعادة كتابة history. يحتفظ task HEAD الحالي `86b3676` أيضاً بالـhook ضمن commit سابق؛ لذلك يجب استبعاده عند إعداد patch المصرح بدمجه، وإلا سيُعاد إدخاله بعد revert. لم يُعدل `render.yaml` في هذه المهمة، ولم يُنفذ revert.

## D. Security Findings Closure

| Finding | المشكلة والسبب | التصحيح والملفات | Regression evidence والنتيجة | القيد المتبقي |
|---|---|---|---|---|
| REV-01 | Settings يقبل casing غير حساس، بينما unset ذو قائمة محدودة يفوّت أسماء أخرى | `app/core/bootstrap_environment.py` يرفض القيم المتعارضة بين variants؛ `scripts/run_runtime.py` يمرر environment صريحاً بلا أي casing للأسماء الأربعة privileged؛ `app/config.py` و`docker-entrypoint.sh` يربطان ذلك بمسار التشغيل | Linux shell حقيقي: upper/lower/mixed/simultaneous/conflicting، مع نجاح وفشل bootstrap وcheck-only؛ probe على Uvicorn المثبت نفسه أثبت غياب owner credentials وبقاء runtime URL. نجحت الاختبارات | الضمان لمسار entrypoint؛ تشغيل Python مباشرة خارجه لا يستفيد منه. يجب عدم تضمين credential-bearing `.env` في الصورة أو mount |
| REV-02 | الفحص السابق لا يغطي كل SET paths والامتيازات التي يمكن الحصول عليها بعد التبديل | `app/core/database_bootstrap.py` يفحص identities القابلة لـSET باستخدام PG16، attributes، ownership، CREATE، table/sequence privileges وrole ADMIN options؛ فحص قبل migrations وبعد hardening | `tests/test_postgres_bootstrap.py`: direct/indirect `INHERIT FALSE, SET TRUE`، ownership لقاعدة/schema/table، CREATEROLE/SUPERUSER/BYPASSRLS، DELETE grant، وADMIN option؛ أُثبت SET ROLE فعلياً ثم رفض bootstrap قبل callback. دور benign مستقل قُبل | التحقق يخص database وschemas التطبيق المعلنة. التغييرات الإدارية اللاحقة تحتاج إعادة فحص؛ لا يحمي من administrator موثوق يغير السياسة بعد startup |
| REV-03 | FORCE RLS قد يجعل SECURITY DEFINER retention يعيد صفراً رغم وجود سجلات مؤهلة | startup يرفض FORCE RLS دون نزعه؛ `scripts/audit_retention.sql` يضيف `row_security=off`؛ verifier يفحص ownership وsearch_path وEXECUTE ACL، ويرفض outsiders وruntime grant option | دعم ordinary RLS، حذف 1000 ثم 200 مع حماية recent rows، FORCE rejection، خطأ retention فعلي بدلاً من zero، ثبات FORCE flag، واختبارات EXECUTE. نجحت | FORCE RLS غير مدعوم عمداً؛ تفعيله لاحقاً يفشل بوضوح. worker يسجل الخطأ ويزيد failure metric بدلاً من اعتبار الحذف ناجحاً |
| REV-04 | lock session منفصل عن Alembic session، فيمكن فقد القفل وبقاء DDL | `bootstrap` يستخدم SQLAlchemy sync connection واحدة للقفل وAlembic وhardening؛ `alembic/env.py` يقبل connection injection؛ NullPool يغلق session في جميع النهايات | healthy concurrent CLIs، revision مؤقت متوقف في SQL مع محاولة ثانية، إثبات أن migration PID نفسه يحمل القفل، `pg_terminate_backend`، rollback للـDDL/version، وفشل العملية الأولى ونجاح recovery للثانية دون duplicate insert. نجحت | migrations الحالية لا تستخدم autocommit blocks أو DDL connections مستقلة. إضافة ذلك مستقبلاً تتطلب مراجعة invariant. migrations قد تكون committed قبل فشل hardening، ويكون recovery بإعادة bootstrap |
| REV-05 | `url.port or 5432` يحول 0 إلى default | `app/core/database_config.py` يستخدم default فقط عند `None` ويتحقق من 1..65535 | `tests/test_database_configuration.py`: 0، negative، oversized، malformed، absent، وحدود/custom ports عبر URL وcomponents. نجحت؛ أخطاء URL لا تعرض credentials | لا يثبت تحقق configuration أن endpoint الفعلي صحيح أو متاح |
| REV-06 | اختبارات PostgreSQL قد تُعد skipped دون منع نجاح CI | workflow يضيف خطوة mandatory؛ runner `--security-only` ينشئ PG16 مستقلاً ويثبت test selection؛ `tests/conftest.py` يفشل عند missing admin/reporter، zero collection، skipped، xfailed أو deselected | آخر تنفيذ لنفس أمر gate محلياً: 124 passed/zero skips؛ negative subprocess tests تؤكد exit 1 عند skip/missing admin/deselection/missing reporter؛ تعطل Docker التجريبي يرجع 1 | GitHub-hosted run غير منفذ لعدم السماح بالـpush؛ branch protection وإلزام status checks في GitHub لم يُفحصا أو يُعدلا |

الـfixed list الخاصة ببعض predefined roles دفاع إضافي؛ الحكم على roles الأخرى يعتمد على attributes وownership وeffective privileges، وليس أسماء مفترضة. تصميم SET/INHERIT يتبع [PostgreSQL 16 role membership](https://www.postgresql.org/docs/16/role-membership.html)، وADMIN يتبع [GRANT semantics](https://www.postgresql.org/docs/16/sql-grant.html). Connection injection يتبع [Alembic cookbook](https://alembic.sqlalchemy.org/en/latest/cookbook.html#sharing-a-connection-across-one-or-more-programmatic-migration-commands).

## E. Architecture Assessment

بقي الفصل بين migration owner وruntime قائماً، دون منح SUPERUSER أو BYPASSRLS أو CREATEROLE لتجاوز الاختبارات. runtime لا يملك audit DELETE؛ التنفيذ الوحيد المصرح للحذف هو function ذات owner موثوق، search_path ثابت، cutoff لا يقصر السياسة، وحد 1000 لكل استدعاء. الحماية لا تدعي منع database owner أو host administrator من تغيير بيانات يسيطر عليها.

القفل والـDDL على session واحدة؛ فقد هذه session يلغي العمل داخل transaction نفسه. migration version tracking يتم مع migration transaction، ثم grants/RLS/function ضمن transaction hardening مستقلة مع استمرار session lock. فشل أي مرحلة يمنع بدء التطبيق، والنجاح يتطلب فحصاً باتصال runtime مستقل. بقي standalone Alembic async path متاحاً دون خلط AsyncConnection وsync Connection.

إزالة credentials آلية واحدة عند exec، مع رفض تعارض casing عند bootstrap. لم تُضف dependencies أو خدمات مدفوعة أو infrastructure دائمة. استُخدمت dependencies الموجودة في worktree؛ لم تُثبت packages في shared virtual environments.

## F. Verification Matrix

كل الأوامر التالية نُفذت من worktree المذكور. `rtk` هو shell prefix المفروض. البيئة الأساسية: Windows، Python 3.12.10، pytest 8.3.4؛ اختبارات PostgreSQL على `postgres:16-alpine` جديد ذي tmpfs وrandom loopback port لكل invocation. اختبارات exec تعمل على Linux فعلي في containers جديدة networkless من image `ironlink-api` الموجودة، وليس داخل API container الجاري.

| الأمر الفعلي | Passed / Failed / Skipped | ما يثبته وحدوده |
|---|---|---|
| `rtk proxy .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider tests/test_database_configuration.py tests/test_bootstrap_environment.py` | 69 / 0 / 0، مع 1 setup error | configuration وLinux shell checks نجحت؛ خطأ Windows shared temp directory منع setup لاختبار واحد؛ عولج بعزل temp directory في runner |
| `rtk proxy .venv\Scripts\python.exe -m scripts.test_postgres_bootstrap -- -q -x -p no:cacheprovider tests/test_postgres_bootstrap.py tests/test_database_configuration.py tests/test_bootstrap_environment.py` | 114 / 0 / 0؛ 117.81s | أول مجموعة focused PG16، تشمل termination/concurrency؛ سبقت إضافة probe Uvicorn وبعض الحالات الإضافية |
| `rtk proxy .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider --basetemp=.venv/mission01a-focused-tmp tests/test_bootstrap_environment.py` | 28 / 1 / 0 | probe Uvicorn فشل لأن app-directory resolution اختار app الحقيقي قبل probe؛ لم يكن فشل credential filter |
| `rtk proxy .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider tests/test_bootstrap_environment.py::test_real_linux_uvicorn_process_receives_no_owner_credentials` | أول إعادة 0 / 1 / 0؛ بعد تصحيح cwd: 1 / 0 / 0؛ بعد فحص empty PORT/WEB_CONCURRENCY: 1 / 0 / 0 | يثبت environment للعملية الحقيقية وdefault behavior للقيم الفارغة؛ ينهي probe عند import قبل فتح server، ولا يثبت production startup كاملاً |
| `rtk proxy .venv\Scripts\python.exe -m scripts.test_postgres_bootstrap --security-only` | 122 / 0 / 0؛ 123.86s | أقرب equivalent محلي لخطوة CI الجديدة؛ ليس GitHub-hosted execution |
| إعادة الأمر نفسه بعد إضافة missing-reporter test | 120 / 4 / 0؛ 719.37s | فشل concurrent CLI بـexit 1 دون diagnostic محفوظ؛ paused-migration marker تجاوز 30s؛ Linux Docker invocation تجاوز 45s؛ والنسخة المحملة القديمة من missing-reporter test أعادت pytest usage exit 4 بسبب `-q`. لا يُحسب هذا run ناجحاً |
| `rtk proxy .venv\Scripts\python.exe -m scripts.test_postgres_bootstrap --security-only` — التنفيذ النهائي بعد targeted recheck | **124 / 0 / 0**؛ 209.72s | يثبت نجاح gate محلياً على النسخة النهائية، بما فيها missing-reporter guard وDocker-outage test؛ أُوقف container الخاص به بنجاح |
| `rtk proxy .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider tests/test_bootstrap_environment.py::test_disposable_runner_fails_when_docker_service_is_unavailable` | 1 / 0 / 0 | runner child استهدف loopback port 1 ورجع exit 1 كما يجب؛ لم يُعدّل Docker daemon أو containers موجودة |
| `rtk proxy .venv\Scripts\python.exe -m scripts.test_postgres_bootstrap -- -q -p no:cacheprovider` | **667 / 0 / 0**؛ 274.18s؛ 7 warnings | Backend regression كاملة مع PostgreSQL حقيقي واختبارات الأمان الأحدث؛ لا تثبت Flutter أو Render أو GitHub-hosted CI |
| `rtk proxy docker run --rm --network none --mount "type=bind,source=C:\Users\Name\.codex\worktrees\mission-01a-postgres-bootstrap\IronLink,target=/task,readonly" --entrypoint sh ironlink-api -n /task/docker-entrypoint.sh` | exit 0 | Linux shell syntax؛ لا يمثل deployment |
| `rtk git diff --check` | exit 0 | لا whitespace errors في tracked diff؛ Python AST parsing شمل 11 ملفاً، وPyYAML نجح للـworkflow مع تأكيد أن gate خطوة غير continue-on-error |

بعد فشل الإعادة، لم تُوسع timeouts أو تُضعف assertions. صُححت CLI options للاختبار الذي يعطل terminal reporter: حذف quiet flags وتصفير pytest addopts في child. أُضيف فشل صريح للـgate عند غياب reporter، مع safe diagnostic وfinally cleanup لعمليات concurrency التي يملكها الاختبار. نجح اختبار missing-reporter منفرداً بعد ذلك. التشخيص المتاح لا يثبت سبب exit 1 التاريخي؛ التباطؤ في Docker وprocess startup ملاحظة متزامنة، وليس دليلاً قاطعاً على السبب.

إعادة الحالات المتأثرة فقط نجحت: **5 passed, 0 failed, 0 skipped** خلال 44.21s، بالأمر الفعلي:

```powershell
rtk proxy .venv\Scripts\python.exe -m scripts.test_postgres_bootstrap -- -q -p no:cacheprovider tests/test_postgres_bootstrap.py::test_concurrent_real_cli_bootstraps_serialize_without_ddl_races tests/test_postgres_bootstrap.py::test_paused_alembic_session_serializes_and_cannot_outlive_its_lock tests/test_bootstrap_environment.py::test_linux_entrypoint_exec_environment[False-false-mixed] tests/test_bootstrap_environment.py::test_mandatory_security_gate_fails_on_skip[missing_reporter]
```

آخر إعادة شاملة للـBackend كانت 667 tests قبل إضافة حالة missing-reporter الأخيرة؛ التغييرات اللاحقة تخص CI test guard وtest diagnostics، وتُتحقق بالـfocused/security gate بدلاً من تكرار Backend كاملة دون ضرورة.

تحذير `pytest_asyncio` عن `asyncio_default_fixture_loop_scope` ظهر عند بدء pytest. التحذيرات السبعة بالمجموعة الكاملة تخص Starlette/AnyIO، pytesseract/pkgutil، PyPDF2 وpython-jose/datetime.utcnow. لم تُعدّل dependencies لإخفائها.

Static checks الإضافية نُفذت عبر `rtk proxy .venv\Scripts\python.exe -c ...` و`rtk proxy python -X utf8 -c ...`: AST للملفات المعدلة، YAML parsing، مقارنة SHA-256 وGit status، وقراءة scoped scanner JSON دون عرض secret values. لم تتوفر `actionlint`؛ لا يُدعى نجاح فحصها.

أمر Python/workflow النهائي كاملاً:

```powershell
rtk proxy .venv\Scripts\python.exe -c "import ast; from pathlib import Path; import yaml; files=['app/config.py','app/core/database_bootstrap.py','app/core/database_config.py','app/core/bootstrap_environment.py','alembic/env.py','scripts/run_runtime.py','scripts/test_postgres_bootstrap.py','tests/conftest.py','tests/test_postgres_bootstrap.py','tests/test_database_configuration.py','tests/test_bootstrap_environment.py']; [ast.parse(Path(p).read_text(encoding='utf-8'),filename=p) for p in files]; doc=yaml.safe_load(Path('.github/workflows/ci.yml').read_text(encoding='utf-8')); assert any(step.get('run')=='python -m scripts.test_postgres_bootstrap --security-only' and not step.get('continue-on-error',False) for step in doc['jobs']['backend']['steps']); print('Final Python AST and workflow YAML checks passed')"
```

أمر scanner الداخلي الفعلي: `gitleaks dir <disposable-scope> --config <worktree>/.gitleaks.toml --no-banner --redact`. scan أول لـ26 ملفاً أعاد exit 1 مع alert واحد على `DB_ENCRYPTION_KEY` الاختباري الموجود مسبقاً في CI؛ أثبتت مقارنة HEAD أنه لم يتغير. Scan تالٍ لـ25 ملفاً كاملة مع newly added CI lines فقط أعاد exit 0، **no leaks found**. لم تُضف allowlist ولم تُقرأ production secret files. هذا دليل scoped، وليس ضماناً لخلو كل history أو البيئة من secrets.

بعد إنشاء التقرير، نجح أيضاً scan نهائي لـ26 ملفاً كاملة تشمل التقرير مع CI additions فقط: **no leaks found**. لم يُستبعد أي سطر CI جديد؛ الاستثناء من full-file scan يخص fixture السابقة المثبت أنها غير معدلة فقط.

## G. Diff Summary

الحالة النهائية: **13 modified tracked files + 14 untracked files = 27**. كانت البداية 12+9. تغير محتوى 11 ملفاً من baseline الموجودة، وأصبح CI tracked file معدلاً، وأُنشئت 3 ملفات كود/اختبارات وملفا evidence/report. الملفات السابقة التي لم تدخل تصحيحاً بقيت كما هي. `render.yaml` لم يتغير في هذه المهمة.

Modified tracked files — مسارات كاملة:

```text
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/.env.example
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/.github/workflows/ci.yml
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/alembic/env.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/config.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/core/database.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/models/audit_log.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/services/retention_worker.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docker-compose.yml
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docker-entrypoint.sh
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/apply_post_migrate.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/init_db.sql
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/post_migrate.sql
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/tests/conftest.py
```

Untracked files — تشمل ملفات implementation السابقة المحفوظة:

```text
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/core/bootstrap_environment.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/core/database_bootstrap.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/app/core/database_config.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docs/MISSION_01A_HARDENING_BASELINE.json
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docs/MISSION_01A_HARDENING_REPORT.md
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/docs/POSTGRES_BOOTSTRAP.md
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/audit_retention.sql
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/bootstrap_database.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/init_local_roles.sh
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/run_runtime.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/scripts/test_postgres_bootstrap.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/tests/test_bootstrap_environment.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/tests/test_database_configuration.py
C:/Users/Name/.codex/worktrees/mission-01a-postgres-bootstrap/IronLink/tests/test_postgres_bootstrap.py
```

تصحيحات هذه المهمة على الملفات الموجودة حصراً: `alembic/env.py`، `app/config.py`، `app/core/database_bootstrap.py`، `app/core/database_config.py`، `docker-entrypoint.sh`، `scripts/audit_retention.sql`، `scripts/test_postgres_bootstrap.py`، `tests/conftest.py`، `tests/test_database_configuration.py`، `tests/test_postgres_bootstrap.py`، `docs/POSTGRES_BOOTSTRAP.md`، وإضافة خطوة إلى `.github/workflows/ci.yml`. بقية التعديلات tracked السابقة لم تُعدل في هذه الجولة.

## H. Remaining Risks

- **Corrected:** تسرب casing variants إلى runtime، SET ROLE/ADMIN escalation ضمن النطاق، silent FORCE RLS retention failure، انفصال lock عن DDL، port-zero fallback، ونجاح CI رغم skipped security tests.
- **Unresolved code issues:** لا ملاحظة مفتوحة من REV-01..REV-06 وفق الأدلة المحلية. الـhook الموجود في task HEAD التزام سابق خارج نطاق تعديل هذه الجولة ويجب حذفه من integration patch الموافق عليه. ليست هذه مراجعة أمنية شاملة لبقية التطبيق.
- **Untested infrastructure assumptions:** GitHub-hosted CI وbranch protection، حسابات PostgreSQL managed الفعلية وgrants الخاصة بها، TLS/endpoints، وصورة Render النهائية لم تُتحقق حياً. لم يُنفذ production deployment.
- **Observed verification limitation:** ظهرت timeouts عند تباطؤ البيئة المحلية في run إضافي ثم نجحت الحالات المتأثرة في cluster جديدة دون تخفيف الحدود. إذا تكرر ذلك في CI يلزم تشخيص الموارد والـstartup latency، ولا يجوز تجاوز الاختبارات أو افتراض نجاح concurrency من exit codes غير محفوظة.
- **Render requirements:** التوفيق بين commitي `42f881f` و`86b3676`، واستخدام startup bootstrap واحد على Free، وتوفير هويتين منفصلتين دون صلاحيات runtime إدارية. لا يكفي standalone Alembic hook لتنفيذ hardening والتحقق.

## I. Proposed Integration Sequence

المراحل التالية اقتراح فقط، ولم يُنفذ شيء منها:

1. بعد موافقة المالك، أنشئ checkout/worktree نظيفاً منفصلاً من deployment branch عند أحدث SHA متحقق، للحفاظ على original checkout المعدل وعلى MISSION 01A worktree كما هما. نفذ normal `git revert 42f881f4e92c23c99255594d9f9cc10112cffa53` هناك، ثم review وcommit/push مصرح بهما؛ لا reset ولا force push.
2. راجع MISSION 01A كاملاً مقابل baseline `654ddb793ab06b78ff3d06f18428f1005b9986ee`، لا مقابل HEAD الحالي وحده؛ فـHEAD `86b3676` يتضمن render changes سابقة. جهز integration patch بلا preDeployCommand، مع إبقاء تصميم credentials الموافق عليه، دون cherry-pick أعمى أو merge للـworktree الحالي.
3. راجع وأقر التصحيحات والاختبارات، ثم نفذ security gate وBackend regression في integration checkout وGitHub Actions بعد push مصرح. راجع آلية branch protection منفصلة عند الحاجة.
4. جهز migration-owner وruntime identities في Render PostgreSQL بواسطة المالك أو provider المخول. احتفظ ببيانات owner السابقة في secret store قبل credential rotation. لا تمنح runtime membership إدارية أو ownership أو audit DELETE، ولا تعتمد على PUBLIC أو تبديل managed default credentials.
5. بعد إقرار configuration، ثبت DATABASE_URL وMIGRATION_DATABASE_URL لنفس host/port/database بهويتين مختلفتين، دون conflicting components أو credentials في image. تحقق من Free blueprint وعدم وجود hook مدفوع، وأن Docker startup يستخدم bootstrap ثم sanitized exec. أي تغيير Render أو نشر يتطلب موافقة منفصلة.
6. نفذ deployment المصرح لاحقاً، ثم تحقق من migration revision وruntime privileges وretention وhealth والإشارات التشغيلية، مع خطة recovery تحفظ الفصل بين الهويات ولا تعيد blanket grants.

## J. Owner Approval Gate

يلزم إقرار المالك قبل: revert أو commit أو push، إعداد integration branch أو دمج patch، إزالة الـhook من configuration النهائية، إنشاء/تعديل database identities أو credentials أو Render environment، أو تشغيل deployment. لم تُطلب موافقة إضافية لإكمال العمل المحلي المصرح به؛ التغييرات الآن uncommitted وقابلة للفحص. لا تبدأ مهمة جديدة تلقائياً.

**IRONLINK MISSION 01A HARDENING COMPLETE — AWAITING OWNER REVIEW AND APPROVAL.**
