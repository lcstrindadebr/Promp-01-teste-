# Interrupção imediata das consultas

Abra o autoinstalador e escolha **6 — Interromper imediatamente e devolver consultas à fila**.

A opção encerra os processos dos serviços apoiarcred-robo e apoiarcred-api, incluindo
navegadores e consultas simultâneas Digi+ (robô/API), ConsigX e Amigoz.
Depois confirma que os executores pararam e devolve os registros ainda em
processando para aguardando. Resultados parciais são limpos para a nova tentativa.
Consultas concluídas e registros já na fila não são alterados.
Não cria consultas, não cobra novamente a cota e preserva o modo API/robô.

Os dois serviços ficam parados, inclusive os endpoints HTTP da aplicação.
O painel estático e o monitor continuam disponíveis. Para retomar:

```bash
sudo systemctl start apoiarcred-robo apoiarcred-api
```

Campanhas pausadas continuam respeitando sua pausa. Os serviços continuam
habilitados para iniciar no próximo boot; esta opção não os desabilita.

Se a conexão com o banco falhar, o comando informa quais filas não foram
recuperadas e retorna erro. Os serviços permanecem parados; corrija a conexão
e execute a opção 6 novamente antes de retomar. A operação é repetível e não
altera registros concluídos entre uma tentativa e outra.

Escopo: instalação padrão com uma VPS executora por projeto Supabase.
Uma chamada já recebida pelo banco externo pode continuar no provedor,
mesmo após o encerramento do processo local; a parada não desfaz essa chamada.
Ao retomar a fila, a consulta pode ser enviada novamente.

Não exige migração SQL. Atualize os arquivos do repositório antes de abrir o menu:

```bash
sudo git -C /opt/apoiarcred-src pull --ff-only origin apoiarcred-consultas-mvp &&
sudo bash /opt/apoiarcred-src/instalar.sh
```

Testes sem serviços reais: `python3 -m unittest discover -s tests -p test_stop_consultas.py -v`.
