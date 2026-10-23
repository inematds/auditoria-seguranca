# FALHAS — auditoria-seguranca

| data | o que quebrou | menor correção | prompt \| infra |
|---|---|---|---|
| 23/10/2026 | teste completo do audita.sh deu "syntax error" no meio: o arquivo foi editado enquanto rodava | testar numa cópia congelada do script | infra |
| 23/10/2026 | sonda nos containers: "awk: command not found" (comparação de versão) | vge em sh puro, sort -u no lugar de awk | infra |
