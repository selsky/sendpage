<html>
<head>
<title>Send Page</title>
</head>
<body>
<!--

$Id$

# Copyright (C) 2000,2001 Kees Cook
# kees@outflux.net, http://outflux.net/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

-->
<h1>Send Page</h1>
<?php
	if (isset($pageto) && $pageto != "" &&
	    isset($pagefrom) && $pagefrom != "" &&
	    isset($pagetext) && $pagetext != "") {
?>
<ul>
<hr>
<?php
		$snpp = popen ("/usr/local/bin/snpp -f ".EscapeShellCmd($pagefrom)." ".EscapeShellCmd($pageto),"w");
		if ($snpp) {
			fwrite ($snpp,$pagetext);
			$ret=(pclose($snpp)>>8)&0xFF;
			$snpp=($ret == 0);
		}
		if (!$snpp) {
?>Sorry, an error occured sending your page!<?php
		}
		else {
?>
Page sent:<br>
<pre>
To: <?php echo stripslashes($pageto) ?>

From: <?php echo stripslashes($pagefrom) ?>

Text:
<?php echo stripslashes($pagetext) ?>
</pre>
<?php
		}
?>
<hr>
</ul>
<?php
	}
?>
Please fill out the following information to send a page....
<p>
<form method="POST" action="<?php print $SCRIPT_NAME ?>">
<table border=0 cellspacing=0 cellpadding=0>
 <tr>
  <td><font<?php if ($pageto=="" && isset($send)) print ' color="#FF0000"'; ?>>To:</font></td>
  <td><input type=text name="pageto" value="<?php echo $pageto ?>" columns="15"><br></td>
 </tr>
 <tr>
  <td><font<?php if ($pagefrom=="" && isset($send)) print ' color="#FF0000"'; ?>>From:</font></td>
  <td><input type=text name="pagefrom" value="<?php echo $pagefrom ?>" columns="40"><br></td>
 </tr>
 <tr>
  <td><font<?php if ($pagetext=="" && isset($send)) print ' color="#FF0000"'; ?>>Text:</font><br></td>
  <td><TEXTAREA NAME="pagetext" ROWS="4" COLS="40" WRAP="SOFT"><?php echo stripslashes($pagetext) ?></TEXTAREA></td>
 </tr>
</table>
<p>
<input type="submit" name="send" value="Send">
</form> 
<hr>
</body>
</html>
