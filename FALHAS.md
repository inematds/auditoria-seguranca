# FALHAS — auditoria-seguranca

| data | o que quebrou | menor correção | prompt \| infra |
|---|---|---|---|
| 23/10/2026 | audita.sh 1.1.1 saía limpo sem concluir: SSH 124/127, container sem shell/ferramenta/timeout e `php -v` vazio não contavam; wget "reset" + site de controle e curl com "certif" na mensagem davam protegido | qualquer teste incompleto = SEM TESTE (saída 2); protegido só por código/mensagem de verificação ou lista sem a raiz; testes/roda.sh com stubs | prompt |
| 23/10/2026 | audita.sh com sudo executava como root node/deno/bun achados em pasta de outro usuário (ex.: /tmp) | ok_exec: caminho inteiro do root/dono sem gravação de outros; binário de usuário via runuser | prompt |
| 23/10/2026 | teste completo do audita.sh deu "syntax error" no meio: o arquivo foi editado enquanto rodava | testar numa cópia congelada do script | infra |
| 23/10/2026 | sonda nos containers: "awk: command not found" (comparação de versão) | vge em sh puro, sort -u no lugar de awk | infra |
