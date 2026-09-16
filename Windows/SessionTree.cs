using System.Windows.Forms;
namespace SunBear;
public sealed class SessionTree : TreeView
{
    readonly HashSet<TreeNode> selected=new();
    TreeNode? anchor;
    bool mouseSelecting;
    public event EventHandler? SelectionChanged;
    public IEnumerable<TreeNode> SelectedNodes=>selected.Where(n=>n.TreeView==this);
    public SessionTree(){DrawMode=TreeViewDrawMode.OwnerDrawText;}
    protected override void OnDrawNode(DrawTreeNodeEventArgs e){
        if(e.Node==null)return;
        bool active=selected.Contains(e.Node);
        using var brush=new SolidBrush(active?Color.FromArgb(218,236,224):BackColor);
        e.Graphics.FillRectangle(brush,e.Bounds);
        TextRenderer.DrawText(e.Graphics,e.Node.Text,Font,e.Bounds,active?Color.FromArgb(22,56,40):ForeColor,TextFormatFlags.VerticalCenter|TextFormatFlags.NoPrefix);
    }
    protected override void OnAfterSelect(TreeViewEventArgs e){base.OnAfterSelect(e);if(!mouseSelecting && e.Node!=null)Choose(e.Node,false,false);}
    protected override void OnMouseDown(MouseEventArgs e){
        var hit=HitTest(e.Location);
        if(hit.Node==null || (hit.Location&TreeViewHitTestLocations.PlusMinus)!=0){base.OnMouseDown(e);return;}
        mouseSelecting=true;try{base.OnMouseDown(e);}finally{mouseSelecting=false;}
        if(e.Button==MouseButtons.Left)Choose(hit.Node,(ModifierKeys&Keys.Control)!=0,(ModifierKeys&Keys.Shift)!=0);
        else if(e.Button==MouseButtons.Right && !selected.Contains(hit.Node))Choose(hit.Node,false,false);
    }
    internal void Choose(TreeNode node,bool control,bool shift){
        selected.RemoveWhere(n=>n.TreeView!=this);
        if(shift && anchor?.TreeView==this){
            var visible=new List<TreeNode>();for(var n=Nodes.Count>0?Nodes[0]:null;n!=null;n=n.NextVisibleNode)visible.Add(n);
            int a=visible.IndexOf(anchor),b=visible.IndexOf(node);
            if(!control)selected.Clear();
            if(a>=0 && b>=0){foreach(var n in visible.Skip(Math.Min(a,b)).Take(Math.Abs(a-b)+1))if(n.Tag is Session)selected.Add(n);}
            else selected.Add(node);
        }else{if(!control)selected.Clear();if(control && selected.Contains(node))selected.Remove(node);else selected.Add(node);anchor=node;}
        Invalidate();SelectionChanged?.Invoke(this,EventArgs.Empty);
    }
}
