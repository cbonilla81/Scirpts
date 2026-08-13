using System;
using System.Drawing;
using System.Windows.Forms;

namespace FolderArchiveTool
{
    public enum ConflictDecision
    {
        Yes,
        YesToAll,
        No,
        NoToAll
    }

    public class ConflictPromptForm : Form
    {
        ConflictDecision _result = ConflictDecision.No;
        public ConflictPromptForm(string message)
        {
            Text = "Conflict";
            Width = 600;
            Height = 170;
            StartPosition = FormStartPosition.CenterParent;

            var lbl = new Label() { Left = 10, Top = 10, Width = 560, Height = 60, Text = message };
            var btnYes = new Button() { Text = "Yes", Left = 40, Top = 80, Width = 100 };
            var btnYesAll = new Button() { Text = "Yes to All", Left = 160, Top = 80, Width = 100 };
            var btnNo = new Button() { Text = "No", Left = 280, Top = 80, Width = 100 };
            var btnNoAll = new Button() { Text = "No to All", Left = 400, Top = 80, Width = 100 };

            btnYes.Click += (s, e) => { _result = ConflictDecision.Yes; DialogResult = DialogResult.OK; Close(); };
            btnYesAll.Click += (s, e) => { _result = ConflictDecision.YesToAll; DialogResult = DialogResult.OK; Close(); };
            btnNo.Click += (s, e) => { _result = ConflictDecision.No; DialogResult = DialogResult.OK; Close(); };
            btnNoAll.Click += (s, e) => { _result = ConflictDecision.NoToAll; DialogResult = DialogResult.OK; Close(); };

            Controls.Add(lbl);
            Controls.Add(btnYes);
            Controls.Add(btnYesAll);
            Controls.Add(btnNo);
            Controls.Add(btnNoAll);
        }

        public static ConflictDecision ShowDialogChoice(IWin32Window owner, string message)
        {
            using var f = new ConflictPromptForm(message);
            var res = f.ShowDialog(owner);
            return f._result;
        }
    }
}
