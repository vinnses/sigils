# Guia de Teste - vscreen Bash Completion

## Instalação para Teste

Antes de testar, instale o completion:

```bash
# Opção 1: Copiar para o sistema
sudo cp spells/vscreen/completions/bash/vscreen.bash /etc/bash_completion.d/vscreen

# Opção 2: Carregar no shell atual (temporário)
source sspells/vscreen/completions/bash/vscreen.bash

# Recarregar bash (se usou opção 1)
exec bash
```

## Método de Teste

Para testar o completion:
1. Digite o comando parcial
2. Pressione `TAB` uma vez (mostra primeira sugestão)
3. Pressione `TAB` duas vezes (mostra todas as sugestões)
4. Use `CTRL+C` para cancelar sem executar

**Notação usada abaixo:**
- `vscreen --out<TAB>` = digite "vscreen --out" e pressione TAB
- `<TAB><TAB>` = pressione TAB duas vezes

---

## TESTE 1: Opções Principais

### 1.1 Listar todas as opções
```bash
vscreen --<TAB><TAB>
```
**Esperado:** Deve mostrar todas as opções principais:
```
--resolution  --size       --output      --change      
--off         --off-all    --purge-modes --list        
--orientation --right-of   --left-of     --above       
--below       --pos        --no-auto     --dry-run     
--debug       --help       --version
```

### 1.2 Completar opção parcial
```bash
vscreen --res<TAB>
```
**Esperado:** Completa para `vscreen --resolution `

```bash
vscreen --ori<TAB>
```
**Esperado:** Completa para `vscreen --orientation `

---

## TESTE 2: Resoluções

### 2.1 Listar IDs de resolução
```bash
vscreen --resolution <TAB><TAB>
```
**Esperado:** Mostra IDs e nomes:
```
1    2    3    4    5    6    
FHD  HD+  HD   HD10 HD+10 SD
```

### 2.2 Completar nome parcial
```bash
vscreen -r FH<TAB>
```
**Esperado:** Completa para `vscreen -r FHD `

```bash
vscreen -r HD<TAB><TAB>
```
**Esperado:** Mostra:
```
HD   HD+  HD10 HD+10
```

---

## TESTE 3: Tamanhos Customizados

### 3.1 Sugestões de tamanho
```bash
vscreen --size <TAB><TAB>
```
**Esperado:** Mostra resoluções comuns:
```
1920x1080  1600x900  1366x768  1280x800  1440x900  800x450
```

### 3.2 Completar tamanho parcial
```bash
vscreen --size 19<TAB>
```
**Esperado:** Completa para `vscreen --size 1920x1080 `

---

## TESTE 4: Output (Dinâmico)

### 4.1 Sem displays ativos (primeira vez)
```bash
vscreen --output <TAB><TAB>
```
**Esperado:** Mostra apenas `1` (primeiro virtual livre)

### 4.2 Com displays ativos
Primeiro ative alguns displays:
```bash
vscreen --output 1 -r 1
vscreen --output 2 -r 2
```

Agora teste:
```bash
vscreen --output <TAB><TAB>
```
**Esperado:** Mostra apenas números livres (ex: `3 4 5 ...`)

### 4.3 Verificar dinamismo
```bash
# Desative um display
vscreen --off 1

# Teste novamente
vscreen --output <TAB><TAB>
```
**Esperado:** Agora `1` deve aparecer novamente na lista

---

## TESTE 5: Change (Apenas Ativos)

### 5.1 Sem displays ativos
```bash
vscreen --change <TAB><TAB>
```
**Esperado:** Nenhuma sugestão ou lista vazia

### 5.2 Com displays ativos
```bash
# Ative alguns displays
vscreen --output 1 -r 1
vscreen --output 3 -r 2
vscreen --output 5 -r 3

# Teste completion
vscreen --change <TAB><TAB>
```
**Esperado:** Mostra apenas: `1 3 5`

### 5.3 Completar número parcial
```bash
vscreen --change 3<TAB>
```
**Esperado:** Completa para `vscreen --change 3 ` (se 3 estiver ativo)

---

## TESTE 6: Off (Apenas Ativos)

Similar ao --change, deve sugerir apenas displays ativos:

```bash
# Com displays 1, 3, 5 ativos
vscreen --off <TAB><TAB>
```
**Esperado:** Mostra: `1 3 5`

```bash
vscreen --off 1<TAB>
```
**Esperado:** Completa para `vscreen --off 1 `

---

## TESTE 7: Orientações

### 7.1 Listar todas as orientações
```bash
vscreen --output 1 -r 1 --orientation <TAB><TAB>
```
**Esperado:** Mostra:
```
L  PR  PL  LF  normal  right  left  inverted
```

### 7.2 Completar orientação
```bash
vscreen -o nor<TAB>
```
**Esperado:** Completa para `vscreen -o normal `

```bash
vscreen -o P<TAB><TAB>
```
**Esperado:** Mostra: `PR  PL`

---

## TESTE 8: Posicionamento

### 8.1 Listar outputs conectados
```bash
vscreen --output 1 -r 1 --right-of <TAB><TAB>
```
**Esperado:** Mostra todos os outputs **conectados** do xrandr:
```
eDP1  VIRTUAL1  HDMI1  # (exemplo - varia por sistema)
```

### 8.2 Testar outras direções
```bash
vscreen --output 2 -r 2 --left-of <TAB><TAB>
vscreen --output 3 -r 3 --above <TAB><TAB>
vscreen --output 4 -r 4 --below <TAB><TAB>
```
**Esperado:** Todos devem mostrar os mesmos outputs conectados

### 8.3 Posições absolutas
```bash
vscreen --output 1 -r 1 --pos <TAB><TAB>
```
**Esperado:** Mostra sugestões comuns:
```
0x0  1920x0  3840x0  0x1080
```

---

## TESTE 9: List Modes

### 9.1 Listar modos
```bash
vscreen --list <TAB><TAB>
```
**Esperado:** Mostra:
```
all  active  free
```

### 9.2 Completar modo
```bash
vscreen --list ac<TAB>
```
**Esperado:** Completa para `vscreen --list active `

---

## TESTE 10: Context-Aware (Inteligente)

### 10.1 Após --output, sugerir opções relacionadas
```bash
vscreen --output 1 <TAB><TAB>
```
**Esperado:** Mostra opções de configuração:
```
-r  --resolution  --size  -o  --orientation  
--right-of  --left-of  --above  --below  --pos  --no-auto
```

### 10.2 Após --change, sugerir opções relacionadas
```bash
vscreen --change 1 <TAB><TAB>
```
**Esperado:** Similar ao --output (opções de configuração)

### 10.3 Após --list, apenas mostrar modos
```bash
vscreen --list <TAB><TAB>
```
**Esperado:** Apenas: `all  active  free`

---

## TESTE 11: Flags Globais

### 11.1 Flags podem aparecer em qualquer posição
```bash
vscreen --debug --output 1 --dry<TAB>
```
**Esperado:** Completa para `vscreen --debug --output 1 --dry-run `

```bash
vscreen --output 1 -r 1 --deb<TAB>
```
**Esperado:** Completa para `vscreen --output 1 -r 1 --debug `

---

## TESTE 12: Verificação de Estado

### 12.1 Teste o ciclo completo

```bash
# 1. Inicialmente, sem displays ativos
vscreen --output <TAB><TAB>          # Deve mostrar: 1 (ou mais)
vscreen --change <TAB><TAB>          # Deve mostrar: nada

# 2. Ativar VIRTUAL1
vscreen --output 1 -r 1

# 3. Verificar mudança
vscreen --output <TAB><TAB>          # Deve mostrar: 2, 3, 4... (sem 1)
vscreen --change <TAB><TAB>          # Deve mostrar: 1
vscreen --off <TAB><TAB>             # Deve mostrar: 1

# 4. Ativar mais displays
vscreen --output 2 -r 2
vscreen --output 5 -r 3

# 5. Verificar estado
vscreen --change <TAB><TAB>          # Deve mostrar: 1, 2, 5
vscreen --output <TAB><TAB>          # Não deve mostrar: 1, 2, 5

# 6. Desativar um
vscreen --off 2

# 7. Verificar novamente
vscreen --change <TAB><TAB>          # Deve mostrar: 1, 5 (sem 2)
vscreen --output <TAB><TAB>          # Deve incluir: 2
```

---

## TESTE 13: Casos Extremos

### 13.1 Múltiplos TABs seguidos
```bash
vscreen --output <TAB><TAB><TAB><TAB>
```
**Esperado:** Deve continuar mostrando a lista sem travar

### 13.2 TAB sem input
```bash
vscreen <TAB><TAB>
```
**Esperado:** Mostra todas as opções principais

### 13.3 Espaço + TAB
```bash
vscreen --resolution <ESPAÇO><TAB><TAB>
```
**Esperado:** Mostra todas as resoluções disponíveis

---

## Checklist Rápido de Validação

Use este checklist para validação rápida:

- [ ] `vscreen --<TAB><TAB>` mostra todas as opções
- [ ] `vscreen -r <TAB><TAB>` mostra todas as resoluções
- [ ] `vscreen --size <TAB><TAB>` mostra tamanhos comuns
- [ ] `vscreen --output <TAB><TAB>` mostra apenas números livres
- [ ] `vscreen --change <TAB><TAB>` mostra apenas números ativos
- [ ] `vscreen --off <TAB><TAB>` mostra apenas números ativos
- [ ] `vscreen -o <TAB><TAB>` mostra orientações
- [ ] `vscreen --right-of <TAB><TAB>` mostra outputs conectados
- [ ] `vscreen --list <TAB><TAB>` mostra modos (all/active/free)
- [ ] Completion funciona em qualquer posição do comando
- [ ] Estado muda dinamicamente ao ativar/desativar displays

---

## Troubleshooting

### Completion não funciona
```bash
# Verificar se foi carregado
complete -p vscreen

# Deve mostrar:
# complete -F _vscreen vscreen
```

### Sugestões erradas
```bash
# Recarregar completion
source ./vscreen-completion.bash

# Verificar outputs xrandr
xrandr | grep VIRTUAL
```

### Nenhuma sugestão para --output
```bash
# Verificar displays disponíveis
xrandr | awk '/^VIRTUAL[0-9]+/ {print $1}'

# Se não houver VIRTUAL outputs, o driver pode não estar configurado
```

---

## Resultado Esperado

✅ **SUCESSO** se:
- Todas as opções completam corretamente
- Sugestões dinâmicas mudam conforme o estado
- Não há erros ou travamentos
- Context-aware funciona (sugere opções apropriadas)

❌ **FALHA** se:
- Sugestões não aparecem
- Mostra opções incorretas
- Não detecta mudanças de estado
- Trava ou gera erros
