import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { IntegrationConfigPanel } from '../IntegrationsStatusPage';

/**
 * SMTP was reachable in theory and unreachable in practice: the catalog entry
 * existed, but no card ever rendered its host field, and the panel was hidden
 * until a secret was present — which a passwordless relay (Mailpit, MailHog, an
 * internal Postfix) never has. So the one transport that needs no vendor account
 * was the one you could not configure.
 */

function renderSmtp(config = {}, onConfigChange = vi.fn()) {
  render(
    <IntegrationConfigPanel
      integrationKey="smtp"
      config={config}
      onConfigChange={onConfigChange}
      hasKey={false}
      isEnabled={false}
    />,
  );
  return onConfigChange;
}

describe('SMTP config panel', () => {
  it('renders with no secret and no prior config — the passwordless-relay case', () => {
    renderSmtp();
    expect(screen.getByLabelText(/Server host/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/^Port$/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Username/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Implicit TLS/i)).toBeInTheDocument();
  });

  it('defaults the port to 587 rather than leaving it blank', () => {
    renderSmtp();
    expect(screen.getByLabelText(/^Port$/i)).toHaveValue(587);
  });

  it('reports the host upward so it reaches site_settings', () => {
    const onChange = renderSmtp();
    fireEvent.change(screen.getByLabelText(/Server host/i), {
      target: { value: 'mailpit.internal' },
    });
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ host: 'mailpit.internal' }));
  });

  it('keeps existing config when one field changes', () => {
    const onChange = renderSmtp({ host: 'smtp.example.com', user: 'noreply@example.com' });
    fireEvent.change(screen.getByLabelText(/^Port$/i), { target: { value: '465' } });
    expect(onChange).toHaveBeenCalledWith({
      host: 'smtp.example.com',
      user: 'noreply@example.com',
      port: 465,
    });
  });

  it('says the password is not stored in the card', () => {
    renderSmtp();
    expect(screen.getByText(/SMTP_PASS/)).toBeInTheDocument();
  });

  it('an unrelated secret-based integration still stays hidden without its key', () => {
    // Guards the widening: only smtp joined the always-show list.
    const { container } = render(
      <IntegrationConfigPanel
        integrationKey="openai"
        config={{}}
        onConfigChange={vi.fn()}
        hasKey={false}
        isEnabled={false}
      />,
    );
    expect(container).toBeEmptyDOMElement();
  });
});
