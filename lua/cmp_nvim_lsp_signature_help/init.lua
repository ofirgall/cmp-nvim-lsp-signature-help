local cmp = require('cmp')

local source = {}

source.new = function()
  return setmetatable({
    signature_help = nil,
  }, { __index = source })
end

source.is_available = function(self)
  return self:_get_client() ~= nil
end

source.get_keyword_pattern = function(self)
  return ([=[\%%(\V%s\m\)\s*\zs]=]):format(table.concat(self:get_trigger_characters(), [[\m\|\V]]))
end

source.get_trigger_characters = function(self)
  local trigger_characters = {}
  for _, c in ipairs(self:_get(self:_get_client().server_capabilities, { 'signatureHelpProvider', 'triggerCharacters' }) or {}) do
    table.insert(trigger_characters, c)
  end
  for _, c in ipairs(self:_get(self:_get_client().server_capabilities, { 'signatureHelpProvider', 'retriggerCharacters' }) or {}) do
    table.insert(trigger_characters, c)
  end
  table.insert(trigger_characters, ' ')
  return trigger_characters
end

source.complete = function(self, params, callback)
  if params.context:get_reason() == cmp.ContextReason.TriggerOnly then
    return callback()
  end

  local client = self:_get_client()
  local trigger_characters = {}
  for _, c in ipairs(self:_get(client.server_capabilities, { 'signatureHelpProvider', 'triggerCharacters' }) or {}) do
    table.insert(trigger_characters, c)
  end
  for _, c in ipairs(self:_get(client.server_capabilities, { 'signatureHelpProvider', 'retriggerCharacters' }) or {}) do
    table.insert(trigger_characters, c)
  end

  local trigger_character = nil
  for _, c in ipairs(trigger_characters) do
    local s, e = string.find(params.context.cursor_before_line, '(' .. vim.pesc(c) .. ')%s*$')
    if s and e then
      trigger_character = string.sub(params.context.cursor_before_line, s, e)
      break
    end
  end
  if not trigger_character then
    return callback({ isIncomplete = true })
  end

  local request = vim.lsp.util.make_position_params(0, self:_get_client().offset_encoding)
  request.context = {
    triggerKind = 2,
    triggerCharacter = trigger_character,
    isRetrigger = not not self.signature_help,
    activeSignatureHelp = self.signature_help,
  }
  client.request('textDocument/signatureHelp', request, function(_, res)
    self.signature_help = res
    callback({
      isIncomplete = true,
      items = self:_items(self.signature_help),
    })
  end)
end

source._items = function(self, signature_help)
  if not signature_help then
    return {}
  end

  local parameter_index = signature_help.activeParameter and signature_help.activeParameter + 1
  local items = {}

  for _, signature in ipairs(signature_help.signatures) do
    local item = self:_item(signature, parameter_index)
    if item then
      table.insert(items, item)
    end
  end

  return items
end

source._item = function(self, signature, parameter_index)
  local parameters = signature.parameters
  if not parameters then
    return nil
  end

  if signature.activeParameter then
    parameter_index = signature.activeParameter + 1
  end

  local arguments = {}
  for i, parameter in ipairs(parameters) do
    if i == parameter_index or not parameter_index then
      table.insert(arguments, self:_parameter_label(signature, parameter))
    end
  end

  if #arguments == 0 then
    return nil
  end

  return {
    label = table.concat(arguments, ', '),
    filterText = '',
    insertText = '',
    preselect = 1,
    documentation = self:_docs(signature, parameter_index),
  }
end

source._docs = function(self, signature, parameter_index)
  local documentation = {}

  if signature.label then
    table.insert(documentation, self:_signature_label(signature, parameter_index))
    table.insert(documentation, '----')
  end

  if type(signature.documentation) == 'table' then
    table.insert(documentation, signature.documentation.value)
  elseif signature.documentation then
    table.insert(documentation, signature.documentation)
  end

  return { kind = 'markdown', value = table.concat(documentation, '\n') }
end

source._signature_label = function(self, signature, parameter_index)
  local label = signature.label
  if parameter_index then
    local s, e = string.find(label, self:_parameter_label(signature, signature.parameters[parameter_index]), 1, true)
    if s and e then
      local active = string.sub(label, s, e)
      label = string.gsub(label, vim.pesc(active), '***' .. active .. '***')
    end
  end
  return label
end

source._parameter_label = function(_, signature, parameter)
  local label = parameter.label
  if type(label) == 'table' then
    label = signature.label:sub(
      1 + vim.str_byteindex(signature.label, label[1]),
      vim.str_byteindex(signature.label, label[2])
    )
  end
  return label
end

source._get_client = function(self)
  for _, client in pairs(vim.lsp.buf_get_clients()) do
    if self:_get(client.server_capabilities, { 'signatureHelpProvider' }) then
      return client
    end
  end
  return nil
end

source._get = function(_, root, paths)
  local c = root
  for _, path in ipairs(paths) do
    c = c[path]
    if not c then
      return nil
    end
  end
  return c
end

return source
