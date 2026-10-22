# TP1 ISI — Sistema Inteligente de Comparação de Preços e Alertas

Pipeline ETL que compara o **custo total real** (preço + portes + câmbio + direitos aduaneiros + IVA de importação + desalfandegamento) de produtos em lojas de quatro países (PT, ES, UK, US), grava o histórico numa base de dados, envia alertas por e-mail quando o custo desce abaixo do preço-alvo de cada utilizador, exporta os resultados para um servidor SFTP e mostra tudo num dashboard Grafana.

> 🎬 **Vídeo de demonstração:**  https://youtu.be/khOgOtvu-xA
>
> 📄 **Relatório:** [`doc/31545_doc.pdf`](doc/31545_doc.pdf)
>
> 💻 **Repositório:** https://github.com/hugo31545/ecommerce-price-tracker-etl

---

## 1. Identificação

| | |
|---|---|
| **Autor** | Hugo Gomes — n.º 31545 |
| **Curso** | Licenciatura em Engenharia de Sistemas Informáticos (LESI), 3.º ano |
| **Unidade Curricular** | Integração de Sistemas de Informação (ISI), 2026/27 |
| **Docentes** | Luís Ferreira |
| **Trabalho** | Trabalho Prático I — processos ETL |

---

## 2. Estrutura e descrição dos ficheiros

```
tp01-31545/
├── README.md                     este ficheiro
├── doc/
│   └── 31545_doc.pdf             relatório final
├── dataintegration/              transformações e jobs ETL (KNIME)
│   ├── 01_extracao/              workflow principal: extração, transformação, carregamento e jobs
│   └── 00_setup_bd.knwf          workflow de apoio que cria a estrutura da base de dados
├── data/
│   ├── input/                    dados de entrada
│   ├── output/                   dados de saída (exemplos gerados pelo pipeline)
│   └── logs/                     logs das execuções
└── src/
    ├── docker/                   infraestrutura (PostgreSQL, Grafana, SFTP, Mailpit)
    ├── sql/                      esquema da base de dados e dump com dados de exemplo
    ├── node-red/                 fluxos Node-RED (stream, conversão YAML, agendamento)
    ├── scripts/                  scripts Windows para preparar, iniciar, executar e parar
    └── grafana/                  dashboard exportado
```

### 2.1 `data/input/` — dados de entrada

| Ficheiro | Formato | Conteúdo |
|---|---|---|
| `loja_pt.csv` | CSV (`;`) | loja portuguesa: EAN, título, preço "x,xx €", portes, stock. Inclui erros propositados (duplicado, EAN com dígito errado, preço em falta, preço negativo) |
| `loja_es.json` | JSON | loja espanhola: preços "x,xx EUR", portes "Gratis" ou valor. Inclui um EAN com a letra O |
| `loja_uk.xml` | XML | loja do Reino Unido: preços e portes em libras (£) |
| `loja_us_base.json` | JSON | preços base da loja dos EUA, usados pelo Node-RED para gerar o stream |
| `loja_us_stream.jsonl` | JSON Lines | **gerado pelo Node-RED**: histórico do stream de preços dos EUA |
| `configuracao.yaml` | YAML | país de destino, lojas e regras de importação |
| `configuracao.json` | JSON | **gerado pelo Node-RED** a partir do YAML (lido pelo KNIME) |
| `precos_alvo.json` | JSON | preços-alvo dos utilizadores (formatos mistos, um e-mail inválido) |
| `precos_alvo.csv` | CSV | preços-alvo dos utilizadores (inclui um EAN inválido) |

### 2.2 `data/output/` — dados de saída

| Ficheiro | Conteúdo |
|---|---|
| `melhores_precos.csv` | melhor loja de cada produto em **todas** as execuções (modo *append*, com data/hora) |
| `melhores_precos_0.json` | melhor loja de cada produto na **última** execução (modo *overwrite*) |

Estes ficheiros são também enviados para o servidor SFTP (`/upload`).

### 2.3 `data/logs/`

| Ficheiro | Conteúdo |
|---|---|
| `execucoes.csv` | uma linha por execução do pipeline (estado OK/ERRO, linhas gravadas, início, fim) |
| `execucoes_anterior.csv` | log das execuções anteriores à reorganização final das pastas |

O mesmo log fica também na tabela `logs_execucao` da base de dados.

### 2.4 `src/`

| Ficheiro | Descrição |
|---|---|
| `docker/docker-compose.yml` | PostgreSQL 16, Grafana, servidor SFTP (atmoz/sftp) e Mailpit (SMTP de testes) |
| `sql/schema.sql` | cria a base de dados **vazia**: tabelas, vistas, triggers que impedem eliminar dados, regras CHECK (preços positivos) |
| `sql/dados_exemplo.sql` | dump completo (`pg_dump`) da base de dados com todo o histórico de execuções |
| `node-red/flows.json` | fluxos Node-RED: conversão YAML → JSON, stream da loja US (endpoint `/loja-us/precos`) e agendamento de hora a hora |
| `scripts/preparar_ambiente.bat` | prepara o projeto numa máquina nova (corre uma vez) |
| `scripts/iniciar.bat` | liga os contentores Docker e o Node-RED |
| `scripts/run_pipeline.bat` | executa o workflow KNIME sem interface (modo batch) |
| `scripts/parar.bat` | desliga o Node-RED e os contentores (os dados ficam guardados) |
| `grafana/dashboard_tp1.json` | dashboard Grafana exportado (6 painéis) |

---

## 3. Ferramentas necessárias

| Ferramenta | Versão usada | Notas |
|---|---|---|
| Windows | 10 / 11 | os scripts `.bat` e a ligação `mklink /J` são para Windows |
| Docker Desktop | recente | com Docker Compose |
| KNIME Analytics Platform | 5.12 | instalação por utilizador (`%LOCALAPPDATA%\Programs\KNIME`) |
| Extensão KNIME *Basic File System Connectors* | 5.12 | nós SSH/SFTP (Install Extensions → pesquisar "SSH") |
| Extensão *NodePit Batch* | 1.1 | execução em batch (ver 4.4) |
| Node.js + Node-RED | Node 24, Node-RED 5.0 | `npm install -g --unsafe-perm node-red` |
| Ligação à Internet | — | APIs Fake Store, Frankfurter (câmbios) e VATComply (IVA) |

### Serviços e credenciais (apenas locais, para demonstração)

| Serviço | Endereço | Credenciais |
|---|---|---|
| PostgreSQL | `localhost:5432`, base de dados `precos` | `etl` / `etl` |
| Grafana | http://localhost:3000 | `admin` / `admin` |
| Mailpit (caixa de e-mail) | http://localhost:8025 (SMTP na porta 1025) | — |
| SFTP | `localhost:2222`, pasta `/upload` | `etl` / `etl` |
| Node-RED | http://localhost:1880 | — |

---

## 4. Como executar

> Todos os caminhos do projeto são **relativos**: a pasta `tp01-31545` pode ser colocada em qualquer lugar.

### 4.1 Preparar (uma vez)

1. Instalar as ferramentas da secção 3.
2. Com o KNIME **fechado**, fazer duplo clique em `src\scripts\preparar_ambiente.bat`.
   Cria a pasta `data\logs` e a ligação `dataintegration\01_extracao\data` → `data`
   (o KNIME só deixa um workflow aceder à sua pasta `data`, a *Workflow Data Area*).
   > A ligação não vai incluída no ZIP de entrega; por isso este passo é obrigatório numa máquina nova.
3. Abrir o Docker Desktop e fazer duplo clique em `src\scripts\iniciar.bat`.
4. **Criar a base de dados** — escolher **uma** das opções, num terminal em `src\docker`:
   - com todo o histórico de exemplo (recomendado, o Grafana fica logo com dados):
     ```
     docker compose exec -T postgres psql -U etl -d precos < ..\sql\dados_exemplo.sql
     ```
   - ou vazia:
     ```
     docker compose exec -T postgres psql -U etl -d precos < ..\sql\schema.sql
     ```
5. **Grafana** (http://localhost:3000, `admin`/`admin`):
   - *Connections → Data sources → Add data source → PostgreSQL*: nome `precos`, host `postgres:5432`, base de dados `precos`, utilizador `etl`/`etl`, *TLS/SSL Mode* `disable` → *Save & test*;
   - *Dashboards → New → Import* → carregar `src\grafana\dashboard_tp1.json` → escolher a fonte de dados `precos` → *Import*.
6. **KNIME**: abrir o KNIME e escolher como *workspace* a pasta `tp01-31545`
   (ou *Menu → Switch workspace*). Abrir o workflow `dataintegration/01_extracao`.

### 4.2 Iniciar e parar os serviços

| Ação | Como |
|---|---|
| Ligar | `src\scripts\iniciar.bat` (Docker Desktop tem de estar aberto) |
| Desligar | `src\scripts\parar.bat` |

⚠️ Nunca usar `docker compose down -v`: o `-v` apaga o volume com a base de dados.

### 4.3 Executar o pipeline na interface do KNIME

No workflow `01_extracao`: **Reset all** → **Execute all** (Shift + F7).
Os nós ficam verdes; o ramo dos e-mails fica inativo quando não há alertas novos (regra das 24 horas).

### 4.4 Executar sem interface (batch)

A KNIME descontinuou o seu Batch Executor gratuito a partir da versão 5.9, por isso é usada a extensão gratuita **NodePit Batch**:

1. No KNIME: *Menu → Preferences → Install/Update → Available Software Sites → Add*
   — Location: `https://download.nodepit.com/5.12`.
2. *Menu → Install extensions* → pesquisar **NodePit Batch** → instalar → reiniciar o KNIME.
3. **Fechar o KNIME** e correr `src\scripts\run_pipeline.bat`.
   O script liga os contentores se for preciso e termina com `Fim (codigo 0)` quando corre bem.

Se o KNIME estiver instalado noutro sítio, alterar a linha `set "KNIME_EXE=..."` do `run_pipeline.bat`.

| Código de saída | Significado |
|---|---|
| 0 | executado com sucesso |
| 1 | Docker Desktop não está a correr |
| 10 | parâmetro inválido |
| 20 | erro ao carregar o workflow |
| 30 | erro ao executar um nó (ver `.metadata\knime\knime.log`) |

### 4.5 Execução agendada (de hora a hora)

No Node-RED (http://localhost:1880), o separador **Agendamento** tem um nó *inject* que, de hora a hora, executa `run_pipeline.bat` através de um nó *exec*.
Para testar de imediato, carregar no botão do nó *De hora a hora*; o resultado aparece no separador de *debug*.
O KNIME tem de estar fechado quando o agendamento dispara.

---

## 5. Verificar os resultados

| O quê | Onde |
|---|---|
| E-mails de alerta | http://localhost:8025 |
| Ficheiros enviados por SFTP | `docker compose exec sftp ls -l /home/etl/upload` (em `src\docker`) |
| Dashboard | http://localhost:3000 → *TP1 — Comparação de Preços* |
| Ficheiros exportados | `data\output\` |
| Logs | `data\logs\execucoes.csv` e tabela `logs_execucao` |

Consultas úteis (em `src\docker`):
```
docker compose exec postgres psql -U etl -d precos -c "SELECT loja, COUNT(*) FROM historico_precos GROUP BY loja;"
docker compose exec postgres psql -U etl -d precos -c "SELECT * FROM v_melhor_loja;"
docker compose exec postgres psql -U etl -d precos -c "SELECT tabela_destino, motivo, COUNT(*) FROM rejeitados GROUP BY 1, 2;"
docker compose exec postgres psql -U etl -d precos -c "SELECT id, estado, linhas, mensagem, fim FROM logs_execucao ORDER BY id DESC LIMIT 5;"
```

---

## 6. Regras de negócio principais

- **Custo total** = preço + portes convertidos para euros; nas lojas fora da UE soma direitos (3 € até 150 €, 2 % acima), IVA de 23 % sobre (valor + direitos) e 2 € de desalfandegamento.
- **Validação**: EAN-13 com dígito de controlo, preço obrigatório e positivo, portes obrigatórios e não negativos (0 = grátis), e-mails válidos. Os registos inválidos ficam na tabela `rejeitados` com o motivo.
- **Alertas** só quando o custo total ≤ preço-alvo, e nunca repetidos dentro de 24 horas.
- **Os dados nunca são eliminados**: triggers no PostgreSQL recusam `DELETE`, `TRUNCATE` e `DROP TABLE`; as alterações às tabelas de referência ficam na tabela `auditoria`; os dados brutos de cada execução ficam em `precos_brutos`.

---

## 7. Resolução de problemas

| Problema | Solução |
|---|---|
| KNIME: *"The specified file … does not exist"* | correr `src\scripts\preparar_ambiente.bat` com o KNIME fechado |
| KNIME: *"Database connection does not exist"* | fazer *Reset* e executar o nó *PostgreSQL Connector* |
| `run_pipeline.bat` falha com a interface do KNIME aberta | fechar o KNIME (o batch usa o mesmo workspace) |
| Grafana: painéis com erro de fonte de dados | editar o painel e escolher a fonte `precos` |
| Node-RED abre sem fluxos | arrancar com `iniciar.bat` (indica o ficheiro `src\node-red\flows.json`) |
| Loja US sem dados | confirmar que o Node-RED está a correr (http://localhost:1880/loja-us/precos) |
| Node-RED mostra `Fim (codigo 20)` no *debug* | a interface do KNIME estava aberta quando o agendamento disparou; fechar o KNIME |
| Mailpit vazio depois de reiniciar os contentores | o Mailpit guarda os e-mails só em memória; os alertas continuam na tabela `alertas` |
