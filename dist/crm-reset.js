const resetAccountPanel = crmElement('section','card crm-reset-panel');
resetAccountPanel.id = 'crmResetPanel';
resetAccountPanel.hidden = true;
resetAccountPanel.innerHTML = `
  <div><h2>Dados da conta</h2><p>Apague os cadastros e o histórico operacional desta conta.</p></div>
  <button type="button" class="crm-danger">Zerar minha conta</button>`;
$('#settings-account').append(resetAccountPanel);

function syncCrmResetAccess() {
  resetAccountPanel.hidden = !authenticated || !currentAccess?.active || currentAccess.role !== 'admin';
}

resetAccountPanel.querySelector('button').onclick = () => {
  syncCrmResetAccess();
  if (resetAccountPanel.hidden) return;
  const epoch = authEpoch;
  const {dialog, form} = crmDialog('Zerar minha conta');
  dialog.classList.add('crm-import-dialog');
  const heading = dialog.querySelector('h2');
  heading.id = 'crmResetTitle';
  dialog.setAttribute('aria-labelledby', heading.id);
  form.innerHTML = `
    <p>Esta ação é permanente. Ela apaga os clientes, vínculos, oportunidades, campanhas, consultas, simulações e o histórico de entregas de webhook da sua conta.</p>
    <p>Seu login, as permissões e as configurações são preservados. Webhooks vinculados a campanhas apagadas ficam desativados.</p>
    <label class="crm-edit-field">Digite ZERAR MINHA CONTA
      <input name="confirmacao" required autocomplete="off" spellcheck="false">
    </label>
    <p role="status"></p>
    <footer><button type="button" data-cancel>Cancelar</button><button type="submit" class="crm-danger" disabled>Apagar dados da conta</button></footer>`;
  const input = form.elements.confirmacao, submit = form.querySelector('[type=submit]');
  const cancel = form.querySelector('[data-cancel]'), close = dialog.querySelector('header button');
  const status = form.querySelector('[role=status]');
  let saving = false;
  input.oninput = () => { submit.disabled = input.value !== 'ZERAR MINHA CONTA'; };
  cancel.onclick = () => dialog.close();
  dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  form.onsubmit = async event => {
    event.preventDefault();
    if (saving || !authenticated || authEpoch !== epoch || currentAccess?.role !== 'admin'
        || input.value !== 'ZERAR MINHA CONTA') return;
    saving = input.disabled = submit.disabled = cancel.disabled = close.disabled = true;
    status.textContent = 'Apagando os dados da conta…';
    try {
      await crmRpc('crm_reset_account', {p_confirmation:input.value});
      if (authEpoch !== epoch) return;
      dialog.close();
      window.location.reload();
    } catch (error) {
      if (authEpoch === epoch) status.textContent = error.message || 'Não foi possível zerar a conta.';
    } finally {
      saving = input.disabled = submit.disabled = cancel.disabled = close.disabled = false;
    }
  };
};
syncCrmResetAccess();
